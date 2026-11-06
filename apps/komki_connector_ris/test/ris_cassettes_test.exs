defmodule KomkiConnectorRis.RisCassettesTest do
  @moduledoc """
  Cassette encryption with fake programs: the real Secure Enclave (Touch
  ID) and the real keychain are never asked — the fake tresor computes
  real AES-256-GCM instead, so the roundtrip is real.
  """

  use ExUnit.Case, async: true

  alias KomkiConnectorRis.RisCassettes

  @canary "GEHEIM-MARKER-42"

  defp tmp_area!(name) do
    # Timestamp AND unique_integer: the latter repeats across VM restarts,
    # so a crashed run could otherwise inherit old counter files and skew
    # the results.
    dir =
      Path.join([
        System.tmp_dir!(),
        "ris-cassettes-#{name}-#{System.system_time(:millisecond)}-#{System.unique_integer([:positive])}"
      ])

    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf(dir) end)
    dir
  end

  # Fake tresor as a wrapper: logs the subcommand (call counter for counting
  # releases) and loads the Elixir script behind it, which computes real
  # AES-256-GCM.
  defp tresor!(dir) do
    script = Path.join(dir, "komki-tresor")
    fake = Path.join(__DIR__, "support/fake_tresor.exs")

    File.write!(script, """
    #!/bin/sh
    echo "$1" >> #{dir}/tresor-calls
    exec elixir #{fake} "$@"
    """)

    File.chmod!(script, 0o755)
    script
  end

  # Small shell fake for exit codes and argv logging.
  defp script!(dir, name, body) do
    script = Path.join(dir, name)
    File.write!(script, "#!/bin/sh\n" <> body <> "\n")
    File.chmod!(script, 0o755)
    script
  end

  # Fake security with a value file instead of the keychain: find-generic-password
  # prints `stored` (exit 44 without it), -i takes the last word of the line.
  defp security!(dir, stored \\ nil) do
    script = Path.join(dir, "security")

    File.write!(script, """
    #!/bin/sh
    echo "$1" >> #{dir}/security-calls
    case "$1" in
      find-generic-password)
        [ -f #{dir}/stored ] || exit 44
        cat #{dir}/stored
        echo
        ;;
      -i)
        read -r line
        printf '%s' "${line##* }" > #{dir}/stored
        ;;
    esac
    """)

    File.chmod!(script, 0o755)
    if stored, do: File.write!(Path.join(dir, "stored"), stored)
    script
  end

  # Standard setup of the seal/unseal tests: install fakes, run init
  # (one release in the fake), return opts.
  defp initialized!(dir) do
    opts = [tresor: tresor!(dir), security: security!(dir)]
    assert {0, _} = RisCassettes.run(["init"], opts)
    opts
  end

  defp cassette!(dir, name, content) do
    file = Path.join(dir, name)
    File.write!(file, content)
    File.chmod!(file, 0o600)
    file
  end

  defp calls(dir, file, subcommand) do
    path = Path.join(dir, file)

    if File.exists?(path),
      do: path |> File.read!() |> String.split("\n") |> Enum.count(&(&1 == subcommand)),
      else: 0
  end

  defp texts(messages), do: Enum.map(messages, fn {_channel, text} -> text end)

  defp mode(file), do: Bitwise.band(File.stat!(file).mode, 0o777)

  describe "init" do
    test "versiegelt den Schluessel und legt das Siegel im Bund ab" do
      dir = tmp_area!("init-ok")
      opts = [tresor: tresor!(dir), security: security!(dir)]

      {0, messages} = RisCassettes.run(["init"], opts)

      stored = Path.join(dir, "stored")
      assert String.starts_with?(File.read!(stored), "ktv1.")
      assert Enum.any?(texts(messages), &(&1 =~ "Secure Enclave"))
      assert calls(dir, "tresor-calls", "check") == 1
      assert calls(dir, "tresor-calls", "seal") == 1
      assert calls(dir, "tresor-calls", "open") == 1
      assert calls(dir, "security-calls", "-i") == 1
    end

    test "verweigert bei vorhandenem Eintrag, ohne den Tresor zu fragen" do
      dir = tmp_area!("init-doppelt")
      tresor = script!(dir, "komki-tresor", "touch #{dir}/marker; exit 0")
      opts = [tresor: tresor, security: security!(dir, "ktv1.schon-da")]

      {1, messages} = RisCassettes.run(["init"], opts)

      assert Enum.any?(texts(messages), &(&1 =~ "security delete-generic-password"))
      refute File.exists?(Path.join(dir, "marker"))
    end

    test "speichert nichts, wenn der Roundtrip-Test scheitert" do
      dir = tmp_area!("init-roundtrip")

      tresor =
        script!(
          dir,
          "komki-tresor",
          """
          case "$1" in
            check) exit 0 ;;
            seal) read -r v; echo "ktv1.$v" ;;
            open) read -r v; echo "voellig-was-anderes" ;;
          esac
          """
        )

      {5, messages} = RisCassettes.run(["init"], tresor: tresor, security: security!(dir))

      assert Enum.any?(texts(messages), &(&1 =~ "Roundtrip-Test fehlgeschlagen"))
      refute File.exists?(Path.join(dir, "stored"))
    end

    test "ohne Tresor: Exit 3" do
      dir = tmp_area!("init-ohne-tresor")

      {3, messages} = RisCassettes.run(["init"], tresor: "/nicht/da", security: security!(dir))

      assert Enum.any?(texts(messages), &(&1 =~ "komki-tresor nicht gefunden"))
    end

    test "Tresor vorhanden, aber nicht ausfuehrbar: Exit 3" do
      dir = tmp_area!("init-tresor-stumm")
      tresor = Path.join(dir, "komki-tresor")
      File.write!(tresor, "kein skript")
      File.chmod!(tresor, 0o644)

      {3, messages} = RisCassettes.run(["init"], tresor: tresor, security: security!(dir))

      assert Enum.any?(texts(messages), &(&1 =~ "nicht ausfuehrbar"))
    end

    test "ohne Secure Enclave: Exit 3" do
      dir = tmp_area!("init-ohne-enclave")

      tresor =
        script!(
          dir,
          "komki-tresor",
          """
          case "$1" in
            check) exit 3 ;;
            *) exit 0 ;;
          esac
          """
        )

      {3, messages} = RisCassettes.run(["init"], tresor: tresor, security: security!(dir))

      assert Enum.any?(texts(messages), &(&1 =~ "keine Secure Enclave"))
    end

    test "Siegel ohne ktv1.-Praefix kommt vom Versiegeln zurueck: Exit 5" do
      dir = tmp_area!("init-bad-seal")

      tresor =
        script!(
          dir,
          "komki-tresor",
          """
          case "$1" in
            check) exit 0 ;;
            *) read -r v; echo "kein-siegel" ;;
          esac
          """
        )

      {5, messages} = RisCassettes.run(["init"], tresor: tresor, security: security!(dir))

      assert Enum.any?(texts(messages), &(&1 =~ "Siegel ungueltig oder von einem anderen Mac"))
    end
  end

  describe "seal/unseal" do
    test "Roundtrip bytetreu: .enc mit Magic und 0600, Klartext geloescht und 0600" do
      dir = tmp_area!("roundtrip")
      opts = initialized!(dir)

      cassettes = %{
        "0001-get-guestmeetings.json" => "{\"request\":\"#{@canary}\"}",
        "0002-post-auth.json" => ~s({"request":{"login":"x"},"response":{"status":200}})
      }

      Enum.each(cassettes, fn {name, content} -> cassette!(dir, name, content) end)
      # One cassette deliberately more open: unseal must restore 0600.
      File.chmod!(Path.join(dir, "0002-post-auth.json"), 0o644)

      {0, seal_messages} = RisCassettes.run(["seal", dir], opts)

      # Messages in processing order: summary first, then files in
      # ascending order.
      assert [
               summary,
               first,
               second
             ] = for({:out, text} <- seal_messages, do: text)

      assert summary =~ "2 Kassette(n) verschluesselt"
      assert first == "verschluesselt: 0001-get-guestmeetings.json"
      assert second == "verschluesselt: 0002-post-auth.json"

      Enum.each(cassettes, fn {name, _content} ->
        enc = Path.join(dir, name <> ".enc")
        assert File.exists?(enc)
        refute File.exists?(Path.join(dir, name))
        assert binary_part(File.read!(enc), 0, 4) == "rkt1"
        assert mode(enc) == 0o600
      end)

      assert calls(dir, "tresor-calls", "open") == 2

      assert {0, _} = RisCassettes.run(["unseal", dir], opts)
      assert calls(dir, "tresor-calls", "open") == 3

      Enum.each(cassettes, fn {name, content} ->
        json = Path.join(dir, name)
        assert File.read!(json) == content
        assert mode(json) == 0o600
        refute File.exists?(Path.join(dir, name <> ".enc"))
      end)
    end

    test "leere Kassetten runden ebenfalls bytetreu" do
      dir = tmp_area!("leer-datei")
      opts = initialized!(dir)
      json = cassette!(dir, "0001-get-x.json", "")

      assert {0, _} = RisCassettes.run(["seal", dir], opts)
      enc = Path.join(dir, "0001-get-x.json.enc")
      assert byte_size(File.read!(enc)) == 4 + 12 + 16
      refute File.exists?(json)

      assert {0, _} = RisCassettes.run(["unseal", dir], opts)
      assert File.read!(json) == ""
    end

    test "Meldungen nennen nie Klartext oder Siegel" do
      dir = tmp_area!("leak")
      opts = [tresor: tresor!(dir), security: security!(dir)]

      {0, init_messages} = RisCassettes.run(["init"], opts)
      seal = File.read!(Path.join(dir, "stored"))
      cassette!(dir, "0001-get-x.json", ~s({"body":"#{@canary}"}))

      {0, seal_messages} = RisCassettes.run(["seal", dir], opts)
      {0, unseal_messages} = RisCassettes.run(["unseal", dir], opts)

      for text <- texts(init_messages ++ seal_messages ++ unseal_messages) do
        refute text =~ @canary
        refute text =~ seal
      end
    end

    test "seal verweigert Kollision (.json neben .json.enc), Freigabe bleibt aus" do
      dir = tmp_area!("kollision-seal")
      opts = [tresor: tresor!(dir), security: security!(dir)]
      cassette!(dir, "0001-get-x.json", "{}")
      File.write!(Path.join(dir, "0001-get-x.json.enc"), "rkt1-alt")

      {1, messages} = RisCassettes.run(["seal", dir], opts)

      assert Enum.any?(texts(messages), &(&1 =~ "0001-get-x.json.enc"))
      assert calls(dir, "tresor-calls", "open") == 0
    end

    test "unseal verweigert bei existierender Klartextdatei" do
      dir = tmp_area!("kollision-unseal")
      opts = initialized!(dir)
      cassette!(dir, "0001-get-x.json", "{}")
      assert {0, _} = RisCassettes.run(["seal", dir], opts)
      File.write!(Path.join(dir, "0001-get-x.json"), "{}")

      {1, messages} = RisCassettes.run(["unseal", dir], opts)

      assert Enum.any?(texts(messages), &(&1 =~ "0001-get-x.json existiert bereits"))
    end

    test "Korruption: Exit 5 mit Dateiname; .enc bleibt liegen" do
      dir = tmp_area!("korruption")
      opts = initialized!(dir)

      # Long enough that position 30 lies in the ciphertext and the last byte in the tag.
      cassette!(dir, "0001-get-x.json", ~s({"k":"v","padding":"0123456789abcdef"}))
      assert {0, _} = RisCassettes.run(["seal", dir], opts)
      enc = Path.join(dir, "0001-get-x.json.enc")

      # Flip the ciphertext
      flip(enc, 30)
      {5, messages} = RisCassettes.run(["unseal", dir], opts)
      assert Enum.any?(texts(messages), &(&1 =~ "korrumpiert oder mit anderem Schluessel"))
      assert File.exists?(enc)

      # Flip the tag
      flip(enc, -1)
      {5, messages} = RisCassettes.run(["unseal", dir], opts)
      assert Enum.any?(texts(messages), &(&1 =~ "korrumpiert"))

      # Flip the magic
      flip(enc, 0)
      {5, messages} = RisCassettes.run(["unseal", dir], opts)
      assert Enum.any?(texts(messages), &(&1 =~ "keine rkt1-Kassette"))

      # Too short, but with correct magic (the earlier flips still stick to the file)
      File.write!(enc, "rkt1zu")
      {5, messages} = RisCassettes.run(["unseal", dir], opts)
      assert Enum.any?(texts(messages), &(&1 =~ "zu kurz"))
    end

    test "Restdatei (.json.new) blockiert unseal mit klarem Namen" do
      dir = tmp_area!("restdatei")
      opts = initialized!(dir)
      cassette!(dir, "0001-get-x.json", "{}")
      assert {0, _} = RisCassettes.run(["seal", dir], opts)
      # Simulates the crash leftover of an aborted unseal.
      File.write!(Path.join(dir, "0001-get-x.json.new"), "alt")

      {1, messages} = RisCassettes.run(["unseal", dir], opts)

      assert Enum.any?(texts(messages), &(&1 =~ "Restdatei 0001-get-x.json.new blockiert"))
      assert File.exists?(Path.join(dir, "0001-get-x.json.enc"))
      # The leftover was not overwritten.
      assert File.read!(Path.join(dir, "0001-get-x.json.new")) == "alt"
    end

    test "Zwischenzustand: seal verschluesselt nur offene Kassetten und laesst .enc in Ruhe" do
      dir = tmp_area!("gemischt")
      opts = initialized!(dir)
      cassette!(dir, "0001-get-a.json", ~s({"a":"#{@canary}"}))
      cassette!(dir, "0002-get-b.json", ~s({"b":2}))
      File.write!(Path.join(dir, "0003-get-c.json.enc"), "rkt1-fremd-fuer-unseal")
      foreign = File.read!(Path.join(dir, "0003-get-c.json.enc"))

      assert {0, _} = RisCassettes.run(["seal", dir], opts)

      assert File.read!(Path.join(dir, "0003-get-c.json.enc")) == foreign

      {0, messages} = RisCassettes.run(["status", dir], opts)
      assert Enum.any?(texts(messages), &(&1 =~ "0 Klartext-Kassette(n), 3 verschluesselt"))
    end

    test "nicht-Kassetten bleiben sichtbar: Warnung beim seal, Zaehler bei status" do
      dir = tmp_area!("sonstige")
      opts = initialized!(dir)
      cassette!(dir, "0001-get-x.json", "{}")
      File.write!(Path.join(dir, "notiz.txt"), "x")

      {0, messages} = RisCassettes.run(["seal", dir], opts)

      assert Enum.any?(texts(messages), &(&1 =~ "notiz.txt" and &1 =~ "bleiben Klartext"))

      {0, status_messages} = RisCassettes.run(["status", dir], opts)

      assert Enum.any?(
               texts(status_messages),
               &(&1 =~ "0 Klartext-Kassette(n), 1 verschluesselt" and &1 =~ "sonstige")
             )
    end

    test "leeres Verzeichnis ist ein Idempotentes nichts-zu-tun (Exit 0)" do
      dir = tmp_area!("leer")
      opts = initialized!(dir)

      {0, seal_messages} = RisCassettes.run(["seal", dir], opts)
      assert Enum.any?(texts(seal_messages), &(&1 =~ "nichts zu tun"))

      {0, unseal_messages} = RisCassettes.run(["unseal", dir], opts)
      assert Enum.any?(texts(unseal_messages), &(&1 =~ "nichts zu tun"))
    end

    test "fehlender Eintrag: Exit 5 mit init-Hinweis" do
      dir = tmp_area!("eintrag-fehlt")
      opts = [tresor: tresor!(dir), security: security!(dir)]
      cassette!(dir, "0001-get-x.json", "{}")

      {5, messages} = RisCassettes.run(["seal", dir], opts)

      assert Enum.any?(texts(messages), &(&1 =~ "zuerst init"))
    end

    test "Klartext-Eintrag im Bund: Exit 5" do
      dir = tmp_area!("eintrag-klartext")
      opts = [tresor: tresor!(dir), security: security!(dir, "kanarien-klartext-eintrag")]
      cassette!(dir, "0001-get-x.json", "{}")

      {5, messages} = RisCassettes.run(["seal", dir], opts)

      assert Enum.any?(texts(messages), &(&1 =~ "kein Siegel"))
    end

    test "Repo-Ablehnung: seal/unseal in einem Git-Repo, nichts wird angefasst" do
      dir = tmp_area!("repo")
      opts = [tresor: tresor!(dir), security: security!(dir)]
      repo_dir = Path.join(__DIR__, "fixtures/replay")
      before = File.ls!(repo_dir)

      {1, messages} = RisCassettes.run(["seal", repo_dir], opts)
      assert Enum.any?(texts(messages), &(&1 =~ "Git-Repo"))
      assert File.ls!(repo_dir) == before

      {1, messages} = RisCassettes.run(["unseal", repo_dir], opts)
      assert Enum.any?(texts(messages), &(&1 =~ "Git-Repo"))

      assert RisCassettes.check_dir(System.tmp_dir!()) == :ok
      assert calls(dir, "tresor-calls", "open") == 0
    end

    test "Symlink in ein Repo umgeht die Pruefung nicht" do
      area = tmp_area!("symlink")
      opts = [tresor: tresor!(area), security: security!(area)]

      repo = Path.join(area, "repo")
      File.mkdir_p!(Path.join(repo, ".git"))
      File.mkdir_p!(Path.join(repo, "cassettes"))
      File.write!(Path.join([repo, "cassettes", "0001-get-x.json"]), "{}")

      live = Path.join(area, "live")
      File.ln_s!(Path.join(repo, "cassettes"), live)

      assert {:error, {:dir_in_repo, _}} = RisCassettes.check_dir(live)

      {1, messages} = RisCassettes.run(["seal", live], opts)
      assert Enum.any?(texts(messages), &(&1 =~ "Git-Repo"))
      refute File.exists?(Path.join([repo, "cassettes", "0001-get-x.json.enc"]))
    end

    test "unlesbares Verzeichnis: klare Meldung statt Crash, auch bei status" do
      area = tmp_area!("unlesbar")
      dir = Path.join(area, "cassettes")
      File.mkdir_p!(dir)
      on_exit(fn -> if File.exists?(dir), do: File.chmod!(dir, 0o755) end)

      File.chmod!(dir, 0o000)

      {1, messages} = RisCassettes.run(["status", dir], [])
      assert Enum.any?(texts(messages), &(&1 =~ "nicht lesbar"))

      {1, messages} = RisCassettes.run(["seal", dir], [])
      assert Enum.any?(texts(messages), &(&1 =~ "nicht lesbar"))

      File.chmod!(dir, 0o755)
    end

    test "ohne Tresor: Exit 3 auch beim seal" do
      dir = tmp_area!("seal-ohne-tresor")
      opts = [tresor: "/nicht/da", security: security!(dir)]
      cassette!(dir, "0001-get-x.json", "{}")

      {3, messages} = RisCassettes.run(["seal", dir], opts)

      assert Enum.any?(texts(messages), &(&1 =~ "komki-tresor nicht gefunden"))
    end

    test "verzeichnis fehlt: Exit 1" do
      dir = tmp_area!("dir-fehlt")

      {1, messages} = RisCassettes.run(["seal", Path.join(dir, "gibts-nicht")], [])

      assert Enum.any?(texts(messages), &(&1 =~ "Verzeichnis fehlt"))
    end
  end

  describe "status" do
    test "zaehlt, ohne tresor oder Schluesselbund zu fragen" do
      dir = tmp_area!("status")
      tresor = script!(dir, "komki-tresor", "touch #{dir}/tresor-marker; exit 0")
      security = script!(dir, "security", "touch #{dir}/security-marker; exit 0")
      cassette!(dir, "0001-get-x.json", "{}")
      File.write!(Path.join(dir, "0002-get-y.json.enc"), "rkt1-egal")

      {0, messages} = RisCassettes.run(["status", dir], tresor: tresor, security: security)

      assert Enum.any?(texts(messages), &(&1 =~ "1 Klartext-Kassette(n), 1 verschluesselt"))
      refute File.exists?(Path.join(dir, "tresor-marker"))
      refute File.exists?(Path.join(dir, "security-marker"))
    end
  end

  describe "check" do
    # check needs neither tresor nor keychain: secrets come from the
    # (fake) config directory, cassettes from the (fake) timestamp tree.
    # env nil means: no .env file at all.
    defp config!(dir, env, token) do
      if env, do: File.write!(Path.join(dir, ".env"), env)
      if token, do: File.write!(Path.join(dir, "token"), token)
      dir
    end

    defp cassette_with_body!(dir, name, response_body) do
      json =
        ~s({"request":{"method":"POST","path":"/auth","query":null,"headers":[],) <>
          ~s("body_b64":"#{Base.encode64("login=redacted")}"},) <>
          ~s("response":{"status":200,"headers":[],"body_b64":"#{Base.encode64(response_body)}"}})

      cassette!(dir, name, json)
    end

    test "findet Geheimnis im dekodierten Antwort-Body: Exit 1" do
      area = tmp_area!("check-body")
      cassettes = tmp_area!("check-body-cassettes")
      config = config!(area, "", @canary)
      cassette_with_body!(cassettes, "0001-post-auth.json", ~s({"token":"#{@canary}"}))

      {code, messages} =
        RisCassettes.run(["check", cassettes], config_dir: config)

      assert code == 1
      lines = texts(messages)

      assert Enum.at(lines, 0) ==
               "ris_cassettes: FUND: token in 0001-post-auth.json (#{Path.basename(cassettes)})"

      assert Enum.at(lines, 1) =~ "1 Kassette(n) geprueft, 1 Fund"
      assert List.last(lines) =~ "Gesamt: 1 Kassette(n) geprueft, 1 Funde"
    end

    test "findet Geheimnis im Rohtext einer Restdatei (.json.new)" do
      area = tmp_area!("check-rest")
      cassettes = tmp_area!("check-rest-cassettes")
      config = config!(area, "", @canary)
      # Crash leftover: not valid JSON, plaintext straight in the file.
      cassette!(cassettes, "0002-get-x.json.new", "crash-rest mit #{@canary} im Klartext")

      {code, messages} = RisCassettes.run(["check", cassettes], config_dir: config)

      assert code == 1
      assert Enum.any?(texts(messages), &(&1 =~ "FUND: token in 0002-get-x.json.new"))
    end

    test "findet Geheimnis im Rohtext einer gueltigen Kassette (Query statt Body)" do
      area = tmp_area!("check-rohtext")
      cassettes = tmp_area!("check-rohtext-dir")
      config = config!(area, "", @canary)

      # Valid JSON; the secret sits in the query string, outside both
      # bodies — only the raw-text part of the scan finds it.
      json =
        ~s({"request":{"method":"GET","path":"/fulltextsearch",) <>
          ~s("query":"searchterm=#{@canary}","headers":[],"body":null},) <>
          ~s("response":{"status":200,"headers":[],"body_b64":"#{Base.encode64(~s({"items":[]}))}"}})

      cassette!(cassettes, "0001-get-fulltextsearch.json", json)

      {code, messages} = RisCassettes.run(["check", cassettes], config_dir: config)

      assert code == 1
      assert Enum.any?(texts(messages), &(&1 =~ "FUND: token in 0001-get-fulltextsearch.json"))
    end

    test ".env-Auswertung wie ratsinfo: first Fundstelle, auch export- und Kommentar-Zeilen" do
      area = tmp_area!("check-env-paritaet")
      cassettes = tmp_area!("check-env-paritaet-dir")

      # Mirrors Ratsinfo.Config.parse_env: unanchored regex, first match
      # wins, no comment handling. A commented-out RIS_PASSWORD is a value
      # ratsinfo would send, so check must search for it; RIS_FOO never
      # counts, whatever the body holds.
      env =
        "# RIS_PASSWORD=alt-kommentiert\n" <>
          "export RIS_EMAIL=wer@web.de\n" <>
          "RIS_FOO=DRIN123\n" <>
          "RIS_EMAIL=#{@canary}\n"

      config = config!(area, env, nil)

      cassette_with_body!(
        cassettes,
        "0001-get-x.json",
        ~s({"a":"wer@web.de","b":"alt-kommentiert","c":"#{@canary}","d":"DRIN123"})
      )

      {code, messages} = RisCassettes.run(["check", cassettes], config_dir: config)

      assert code == 1
      lines = texts(messages)

      # First occurrence wins: the export-RIS_EMAIL counts, the later
      # RIS_EMAIL (@canary) does not. The commented password is searched.
      assert Enum.any?(lines, &(&1 =~ "FUND: RIS_EMAIL in 0001-get-x.json"))
      assert Enum.any?(lines, &(&1 =~ "FUND: RIS_PASSWORD in 0001-get-x.json"))
      assert Enum.count(lines, &(&1 =~ "FUND:")) == 2
      refute Enum.any?(lines, &(&1 =~ "FUND: RIS_FOO"))
    end

    test "sauber: Exit 0, Zaehler stimmen" do
      area = tmp_area!("check-clean")
      cassettes = tmp_area!("check-clean-cassettes")

      # Fake placeholder values; the test file is path-allowlisted in
      # .gitleaks.toml, so the literal stays readable instead of being
      # split into string fragments.
      config = config!(area, "RIS_EMAIL=wer@web.de\nRIS_PASSWORD=streg\n", "tok")
      cassette_with_body!(cassettes, "0001-get-x.json", ~s({"items":[]}))
      cassette_with_body!(cassettes, "0002-get-y.json", ~s({"items":[]}))

      {code, messages} = RisCassettes.run(["check", cassettes], config_dir: config)

      assert code == 0
      assert Enum.any?(texts(messages), &(&1 =~ "2 Kassette(n) geprueft, 0 Fund"))
      assert List.last(texts(messages)) =~ "Gesamt: 2 Kassette(n) geprueft, 0 Funde"
    end

    test "Meldungen nennen nie Geheimnis-Werte" do
      area = tmp_area!("check-leak")
      cassettes = tmp_area!("check-leak-cassettes")
      config = config!(area, "RIS_PASSWORD=#{@canary}\n", @canary)
      cassette_with_body!(cassettes, "0001-post-auth.json", ~s({"password":"#{@canary}"}))

      {1, messages} = RisCassettes.run(["check", cassettes], config_dir: config)

      for text <- texts(messages) do
        refute text =~ @canary
      end
    end

    test "verschluesseltes Verzeichnis: uebersprungen, Exit 0" do
      area = tmp_area!("check-encrypted")
      cassettes = tmp_area!("check-encrypted-dir")
      config = config!(area, "", @canary)
      File.write!(Path.join(cassettes, "0001-get-x.json.enc"), "rkt1-chiffre")

      {code, messages} = RisCassettes.run(["check", cassettes], config_dir: config)

      assert code == 0

      assert Enum.any?(
               texts(messages),
               &(&1 =~ "kein Klartext (verschluesselt oder leer), uebersprungen")
             )
    end

    test "Mischverzeichnis: Chiffre wird gezaehlt und gemeldet, Klartext geprueft" do
      area = tmp_area!("check-gemischt")
      cassettes = tmp_area!("check-gemischt-dir")
      config = config!(area, "", @canary)

      cassette_with_body!(cassettes, "0001-get-a.json", ~s({"ok":1}))
      File.write!(Path.join(cassettes, "0002-get-b.json.enc"), "rkt1-chiffre")
      File.write!(Path.join(cassettes, "0003-get-c.json.enc.new"), "rkt1-chiffre-rest")

      {code, messages} = RisCassettes.run(["check", cassettes], config_dir: config)

      assert code == 0

      assert Enum.any?(
               texts(messages),
               &(&1 =~ "1 Kassette(n) geprueft, 2 verschluesselt uebersprungen, 0 Funde")
             )
    end

    test "ohne Verzeichnis: alle Zeitstempel-Baum-Unterverzeichnisse, Chiffre-Reste zaehlen nicht" do
      area = tmp_area!("check-base")
      base = tmp_area!("check-base-baum")
      config = config!(area, "", @canary)

      clean = Path.join(base, "20261101T090000Z")
      hit = Path.join(base, "20261101T090500Z")
      encrypted = Path.join(base, "20261101T091000Z")
      Enum.each([clean, hit, encrypted], &File.mkdir_p!/1)
      cassette_with_body!(clean, "0001-get-a.json", ~s({"ok":1}))
      cassette_with_body!(hit, "0001-get-b.json", ~s({"token":"#{@canary}"}))
      File.write!(Path.join(hit, "0002-get-c.json.enc.new"), "rkt1-chiffre-rest")
      File.write!(Path.join(encrypted, "0001-get-d.json.enc"), "rkt1-chiffre")

      # Not a timestamp directory: no recording session, not scanned —
      # its plaintext secret must not surface as a FUND.
      backup = Path.join(base, "backup-notizen")
      File.mkdir_p!(backup)
      cassette_with_body!(backup, "0001-get-z.json", ~s({"token":"#{@canary}"}))

      {code, messages} = RisCassettes.run(["check"], config_dir: config, cassette_base: base)
      lines = texts(messages)

      assert code == 1
      assert Enum.count(lines, &(&1 =~ "FUND:")) == 1
      assert Enum.any?(lines, &(&1 =~ "20261101T090000Z: 1 Kassette(n) geprueft, 0 Fund"))

      assert Enum.any?(
               lines,
               &(&1 =~
                   "20261101T090500Z: 1 Kassette(n) geprueft, 1 verschluesselt uebersprungen, 1 Fund")
             )

      assert Enum.any?(lines, &(&1 =~ "20261101T091000Z: kein Klartext"))

      assert List.last(lines) =~
               "Gesamt: 2 Kassette(n) geprueft, 1 Funde, 1 Verzeichnis(se) uebersprungen"
    end

    test "Sammel-Verzeichnis ohne eigenen Klartext: laeuft die Unterverzeichnisse" do
      area = tmp_area!("check-sammel")
      base = tmp_area!("check-sammel-baum")
      config = config!(area, "", @canary)
      child = Path.join(base, "20261101T093000Z")
      File.mkdir_p!(child)
      cassette_with_body!(child, "0001-get-a.json", ~s({"token":"#{@canary}"}))

      # base itself holds no cassettes, only the subdirectory does.
      {code, messages} = RisCassettes.run(["check", base], config_dir: config)

      assert code == 1
      assert Enum.any?(texts(messages), &(&1 =~ "FUND: token in 0001-get-a.json"))
    end

    test "Klartext vorhanden, aber kein Geheimnis ladbar: Exit 1, nichts geprueft" do
      area = tmp_area!("check-ohne-geheimnisse")
      cassettes = tmp_area!("check-ohne-geheimnisse-dir")
      config = config!(area, "", nil)
      cassette_with_body!(cassettes, "0001-get-x.json", ~s({"egal":1}))

      {code, messages} = RisCassettes.run(["check", cassettes], config_dir: config)

      assert code == 1
      assert Enum.any?(texts(messages), &(&1 =~ "keine Geheimnisse aus"))
      assert Enum.any?(texts(messages), &(&1 =~ "blieben ungeprueft"))
    end

    test "fehlende .env-Datei: derselbe klare Ausgang wie eine leere" do
      area = tmp_area!("check-env-fehlt")
      cassettes = tmp_area!("check-env-fehlt-dir")
      # Neither .env nor token file exists.
      config = config!(area, nil, nil)
      cassette_with_body!(cassettes, "0001-get-x.json", ~s({"egal":1}))

      {code, messages} = RisCassettes.run(["check", cassettes], config_dir: config)

      assert code == 1
      assert Enum.any?(texts(messages), &(&1 =~ "keine Geheimnisse aus"))
      assert Enum.any?(texts(messages), &(&1 =~ "blieben ungeprueft"))
    end

    test "unlesbare Kassette: Meldung und Exit 1, Rest laeuft weiter" do
      area = tmp_area!("check-unlesbar")
      cassettes = tmp_area!("check-unlesbar-dir")
      config = config!(area, "", @canary)
      cassette_with_body!(cassettes, "0001-get-a.json", ~s({"ok":1}))
      locked = Path.join(cassettes, "0002-get-b.json")
      File.write!(locked, ~s({"x":"#{@canary}"}))
      File.chmod!(locked, 0o000)

      {code, messages} = RisCassettes.run(["check", cassettes], config_dir: config)

      assert code == 1
      lines = texts(messages)
      assert Enum.any?(lines, fn z -> z =~ "0002-get-b.json" and z =~ "unlesbar" end)
      assert Enum.any?(lines, &(&1 =~ "1 Kassette(n) geprueft, 1 unlesbar"))
      assert List.last(lines) =~ "Gesamt: 1 Kassette(n) geprueft, 0 Funde, 1 unlesbar"

      File.chmod!(locked, 0o600)
    end

    test "fehlendes Verzeichnis: Exit 1" do
      area = tmp_area!("check-fehlt")
      config = config!(area, "", @canary)

      {code, messages} =
        RisCassettes.run(["check", Path.join(area, "gibts-nicht")], config_dir: config)

      assert code == 1
      assert Enum.any?(texts(messages), &(&1 =~ "Verzeichnis fehlt"))
    end

    test "--tresor ohne Wert: Exit 2 mit Usage" do
      {code, messages} = RisCassettes.run(["check", "--tresor"], [])

      assert code == 2
      assert Enum.any?(texts(messages), &(&1 =~ "Aufruf:"))
    end
  end

  describe "tresor-Protokoll" do
    test "Exit-Codes werden zu Gruenden (3/4/5/9)" do
      dir = tmp_area!("exit-codes")

      for {code, reason} <- [{3, :no_enclave}, {4, :refused}, {5, :invalid}, {9, {:failed, 9}}] do
        cmd = script!(dir, "tresor-#{code}", "read -r v; exit #{code}")
        assert {:error, ^reason} = RisCassettes.tresor_open("ktv1.x", "Test", tresor: cmd)
      end

      assert :ok = RisCassettes.tresor_check(script!(dir, "tresor-ok", "exit 0"))
      assert {:error, :no_enclave} = RisCassettes.tresor_check(script!(dir, "tresor-3", "exit 3"))
    end

    test "check haengt nicht: Timeout beendet das Programm" do
      dir = tmp_area!("check-timeout")
      cmd = script!(dir, "komki-tresor", "exec sleep 30")

      assert {:error, :timeout} = RisCassettes.tresor_check(cmd, check_timeout: 300)
    end

    test "Klartext und Siegel gehen nie ueber argv" do
      dir = tmp_area!("argv")

      seal_cmd =
        script!(dir, "tresor-argv-seal", ~s(echo "$@" > #{dir}/argv; read -r v; echo ktv1.x))

      assert {:ok, _} = RisCassettes.tresor_seal("kanarienwert", tresor: seal_cmd)
      assert File.read!(Path.join(dir, "argv")) == "seal\n"

      open_cmd =
        script!(dir, "tresor-argv-open", ~s(echo "$@" > #{dir}/argv; read -r v; echo offen))

      assert {:ok, _} =
               RisCassettes.tresor_open("ktv1.siegelwert", "Grund fuer die Karte",
                 tresor: open_cmd
               )

      argv = File.read!(Path.join(dir, "argv"))
      assert argv == "open --reason Grund fuer die Karte\n"
      refute argv =~ "ktv1.siegelwert"
    end

    test "Timeout beendet das Programm ohne Freigabe" do
      dir = tmp_area!("timeout")
      cmd = script!(dir, "komki-tresor", "exec sleep 30")

      assert {:error, :timeout} =
               RisCassettes.tresor_open("ktv1.x", "Test", tresor: cmd, open_timeout: 300)
    end
  end

  describe "Aufruf" do
    test "falsche Aufrufe: Exit 2 mit Usage" do
      for argv <- [
            [],
            ["nix"],
            ["seal"],
            ["seal", "a", "b"],
            ["init", "verzeichnis"],
            # --tresor without a value would otherwise be the path
            ["seal", "--tresor"]
          ] do
        {2, messages} = RisCassettes.run(argv, [])
        assert Enum.any?(texts(messages), &(&1 =~ "Aufruf:"))
      end
    end

    test "--tresor-Flag haelt den Prozesspfad bis zur Ausfuehrung" do
      assert {:ok, {"seal", "/irgend/wo", [tresor: "/bin/tresor"]}} =
               RisCassettes.parse_cli(["seal", "/irgend/wo", "--tresor", "/bin/tresor"])

      assert {:ok, {"init", nil, [tresor: "/bin/tresor"]}} =
               RisCassettes.parse_cli(["init", "--tresor", "/bin/tresor"])
    end
  end

  defp flip(file, at) do
    blob = File.read!(file)
    pos = if at < 0, do: byte_size(blob) + at, else: at
    byte = :binary.at(blob, pos)

    changed =
      binary_part(blob, 0, pos) <>
        <<Bitwise.bxor(byte, 0xFF)>> <>
        binary_part(blob, pos + 1, byte_size(blob) - pos - 1)

    File.write!(file, changed)
  end
end
