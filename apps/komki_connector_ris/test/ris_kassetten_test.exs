defmodule KomkiConnectorRis.RisKassettenTest do
  @moduledoc """
  Kassetten-Verschluesselung mit Fake-Programmen: die echte Secure Enclave
  (Touch ID) und der echte Schluesselbund werden nie gefragt — der Fake-tresor
  rechnet dafuer echtes AES-256-GCM, damit der Rundweg real ist.
  """

  use ExUnit.Case, async: true

  alias KomkiConnectorRis.RisKassetten

  @kanarie "GEHEIM-MARKER-42"

  defp tmp_area!(name) do
    dir =
      Path.join([
        System.tmp_dir!(),
        "ris-kassetten-#{name}-#{System.unique_integer([:positive])}"
      ])

    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf(dir) end)
    dir
  end

  # Fake-tresor als Wrapper: schreibt das Subkommando nach (Aufrufzaehler fuer
  # die Freigabe-Zaehlung) und laedt das Elixir-Skript dahinter, das echtes
  # AES-256-GCM rechnet.
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

  # Kleiner Shell-Fake fuer Exit-Codes und argv-Protokoll.
  defp script!(dir, name, body) do
    script = Path.join(dir, name)
    File.write!(script, "#!/bin/sh\n" <> body <> "\n")
    File.chmod!(script, 0o755)
    script
  end

  # Fake-security mit Wert-Datei statt Schluesselbund: find-generic-password
  # gibt `stored` aus (Exit 44 ohne), -i uebernimmt das letzte Wort der Zeile.
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

  defp kassette!(dir, name, content) do
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

  defp texts(meldungen), do: Enum.map(meldungen, fn {_kanal, text} -> text end)

  defp mode(file), do: Bitwise.band(File.stat!(file).mode, 0o777)

  describe "init" do
    test "versiegelt den Schluessel und legt das Siegel im Bund ab" do
      dir = tmp_area!("init-ok")
      opts = [tresor: tresor!(dir), security: security!(dir)]

      {0, meldungen} = RisKassetten.run(["init"], opts)

      stored = Path.join(dir, "stored")
      assert String.starts_with?(File.read!(stored), "ktv1.")
      assert Enum.any?(texts(meldungen), &(&1 =~ "Secure Enclave"))
      assert calls(dir, "tresor-calls", "check") == 1
      assert calls(dir, "tresor-calls", "seal") == 1
      assert calls(dir, "tresor-calls", "open") == 1
      assert calls(dir, "security-calls", "-i") == 1
    end

    test "verweigert bei vorhandenem Eintrag, ohne den Tresor zu fragen" do
      dir = tmp_area!("init-doppelt")
      tresor = script!(dir, "komki-tresor", "touch #{dir}/marker; exit 0")
      opts = [tresor: tresor, security: security!(dir, "ktv1.schon-da")]

      {1, meldungen} = RisKassetten.run(["init"], opts)

      assert Enum.any?(texts(meldungen), &(&1 =~ "security delete-generic-password"))
      refute File.exists?(Path.join(dir, "marker"))
    end

    test "speichert nichts, wenn die Rundweg-Kontrolle scheitert" do
      dir = tmp_area!("init-rundweg")

      tresor =
        script!(dir, "komki-tresor", """
        case "$1" in
          check) exit 0 ;;
          seal) read -r v; echo "ktv1.$v" ;;
          open) read -r v; echo "voellig-was-anderes" ;;
        esac
        """)

      {5, meldungen} = RisKassetten.run(["init"], tresor: tresor, security: security!(dir))

      assert Enum.any?(texts(meldungen), &(&1 =~ "Rundweg-Kontrolle fehlgeschlagen"))
      refute File.exists?(Path.join(dir, "stored"))
    end

    test "ohne Tresor: Exit 3" do
      dir = tmp_area!("init-ohne-tresor")

      {3, meldungen} = RisKassetten.run(["init"], tresor: "/nicht/da", security: security!(dir))

      assert Enum.any?(texts(meldungen), &(&1 =~ "komki-tresor nicht gefunden"))
    end

    test "ohne Secure Enclave: Exit 3" do
      dir = tmp_area!("init-ohne-enclave")

      tresor =
        script!(dir, "komki-tresor", """
        case "$1" in
          check) exit 3 ;;
          *) exit 0 ;;
        esac
        """)

      {3, meldungen} = RisKassetten.run(["init"], tresor: tresor, security: security!(dir))

      assert Enum.any?(texts(meldungen), &(&1 =~ "keine Secure Enclave"))
    end

    test "Siegel ohne ktv1.-Praefix kommt vom Versiegeln zurueck: Exit 5" do
      dir = tmp_area!("init-bad-seal")

      tresor =
        script!(dir, "komki-tresor", """
        case "$1" in
          check) exit 0 ;;
          *) read -r v; echo "kein-siegel" ;;
        esac
        """)

      {5, meldungen} = RisKassetten.run(["init"], tresor: tresor, security: security!(dir))

      assert Enum.any?(texts(meldungen), &(&1 =~ "Siegel ungueltig oder von einem anderen Mac"))
    end
  end

  describe "seal/unseal" do
    test "Rundweg bytetreu: .enc mit Magic und 0600, Klartext geloescht und 0600" do
      dir = tmp_area!("rundweg")
      opts = [tresor: tresor!(dir), security: security!(dir)]
      assert {0, _} = RisKassetten.run(["init"], opts)

      kassetten = %{
        "0001-get-guestmeetings.json" => "{\"request\":\"#{@kanarie}\"}",
        "0002-post-auth.json" => ~s({"request":{"login":"x"},"response":{"status":200}})
      }

      Enum.each(kassetten, fn {name, content} -> kassette!(dir, name, content) end)
      # Eine Kassette bewusst weiter offen: unseal muss 0600 wiederherstellen.
      File.chmod!(Path.join(dir, "0002-post-auth.json"), 0o644)

      assert {0, _} = RisKassetten.run(["seal", dir], opts)

      Enum.each(kassetten, fn {name, _content} ->
        enc = Path.join(dir, name <> ".enc")
        assert File.exists?(enc)
        refute File.exists?(Path.join(dir, name))
        assert binary_part(File.read!(enc), 0, 4) == "rkt1"
        assert mode(enc) == 0o600
      end)

      assert calls(dir, "tresor-calls", "open") == 2

      assert {0, _} = RisKassetten.run(["unseal", dir], opts)
      assert calls(dir, "tresor-calls", "open") == 3

      Enum.each(kassetten, fn {name, content} ->
        json = Path.join(dir, name)
        assert File.read!(json) == content
        assert mode(json) == 0o600
        refute File.exists?(Path.join(dir, name <> ".enc"))
      end)
    end

    test "Meldungen nennen nie Klartext oder Siegel" do
      dir = tmp_area!("leak")
      opts = [tresor: tresor!(dir), security: security!(dir)]

      {0, init_meldungen} = RisKassetten.run(["init"], opts)
      siegel = File.read!(Path.join(dir, "stored"))
      kassette!(dir, "0001-get-x.json", ~s({"body":"#{@kanarie}"}))

      {0, seal_meldungen} = RisKassetten.run(["seal", dir], opts)
      {0, unseal_meldungen} = RisKassetten.run(["unseal", dir], opts)

      for text <- texts(init_meldungen ++ seal_meldungen ++ unseal_meldungen) do
        refute text =~ @kanarie
        refute text =~ siegel
      end
    end

    test "seal verweigert Kollision (.json neben .json.enc), Freigabe bleibt aus" do
      dir = tmp_area!("kollision-seal")
      opts = [tresor: tresor!(dir), security: security!(dir)]
      kassette!(dir, "0001-get-x.json", "{}")
      File.write!(Path.join(dir, "0001-get-x.json.enc"), "rkt1-alt")

      {1, meldungen} = RisKassetten.run(["seal", dir], opts)

      assert Enum.any?(texts(meldungen), &(&1 =~ "0001-get-x.json.enc"))
      assert calls(dir, "tresor-calls", "open") == 0
    end

    test "unseal verweigert bei existierender Klartextdatei" do
      dir = tmp_area!("kollision-unseal")
      opts = [tresor: tresor!(dir), security: security!(dir)]
      assert {0, _} = RisKassetten.run(["init"], opts)
      kassette!(dir, "0001-get-x.json", "{}")
      assert {0, _} = RisKassetten.run(["seal", dir], opts)
      File.write!(Path.join(dir, "0001-get-x.json"), "{}")

      {1, meldungen} = RisKassetten.run(["unseal", dir], opts)

      assert Enum.any?(texts(meldungen), &(&1 =~ "0001-get-x.json existiert bereits"))
    end

    test "Korruption: Exit 5 mit Dateiname; .enc bleibt liegen" do
      dir = tmp_area!("korruption")
      opts = [tresor: tresor!(dir), security: security!(dir)]
      assert {0, _} = RisKassetten.run(["init"], opts)
      # Lang genug, dass Position 30 im Chiffretext liegt und das letzte Byte im Tag.
      kassette!(dir, "0001-get-x.json", ~s({"k":"v","padding":"0123456789abcdef"}))
      assert {0, _} = RisKassetten.run(["seal", dir], opts)
      enc = Path.join(dir, "0001-get-x.json.enc")

      # Chiffretext kippen
      flip(enc, 30)
      {5, meldungen} = RisKassetten.run(["unseal", dir], opts)
      assert Enum.any?(texts(meldungen), &(&1 =~ "korrumpiert oder mit anderem Schluessel"))
      assert File.exists?(enc)

      # Tag kippen
      flip(enc, -1)
      {5, meldungen} = RisKassetten.run(["unseal", dir], opts)
      assert Enum.any?(texts(meldungen), &(&1 =~ "korrumpiert"))

      # Magic kippen
      flip(enc, 0)
      {5, meldungen} = RisKassetten.run(["unseal", dir], opts)
      assert Enum.any?(texts(meldungen), &(&1 =~ "keine rkt1-Kassette"))

      # Zu kurz, aber mit korrekter Magic (die vorigen Flips haengen noch an der Datei)
      File.write!(enc, "rkt1zu")
      {5, meldungen} = RisKassetten.run(["unseal", dir], opts)
      assert Enum.any?(texts(meldungen), &(&1 =~ "zu kurz"))
    end

    test "Mischzustand: seal versiegelt nur offene Kassetten und laesst .enc in Ruhe" do
      dir = tmp_area!("gemischt")
      opts = [tresor: tresor!(dir), security: security!(dir)]
      assert {0, _} = RisKassetten.run(["init"], opts)
      kassette!(dir, "0001-get-a.json", ~s({"a":"#{@kanarie}"}))
      kassette!(dir, "0002-get-b.json", ~s({"b":2}))
      File.write!(Path.join(dir, "0003-get-c.json.enc"), "rkt1-fremd-fuer-unseal")
      fremd = File.read!(Path.join(dir, "0003-get-c.json.enc"))

      assert {0, _} = RisKassetten.run(["seal", dir], opts)

      assert File.read!(Path.join(dir, "0003-get-c.json.enc")) == fremd

      {0, meldungen} = RisKassetten.run(["status", dir], opts)
      assert Enum.any?(texts(meldungen), &(&1 =~ "0 Klartext-Kassette(n), 3 versiegelt"))
    end

    test "leeres Verzeichnis ist ein Idempotentes nichts-zu-tun (Exit 0)" do
      dir = tmp_area!("leer")
      opts = [tresor: tresor!(dir), security: security!(dir)]
      assert {0, _} = RisKassetten.run(["init"], opts)

      {0, seal_meldungen} = RisKassetten.run(["seal", dir], opts)
      assert Enum.any?(texts(seal_meldungen), &(&1 =~ "nichts zu tun"))

      {0, unseal_meldungen} = RisKassetten.run(["unseal", dir], opts)
      assert Enum.any?(texts(unseal_meldungen), &(&1 =~ "nichts zu tun"))
    end

    test "fehlender Eintrag: Exit 5 mit init-Hinweis" do
      dir = tmp_area!("eintrag-fehlt")
      opts = [tresor: tresor!(dir), security: security!(dir)]
      kassette!(dir, "0001-get-x.json", "{}")

      {5, meldungen} = RisKassetten.run(["seal", dir], opts)

      assert Enum.any?(texts(meldungen), &(&1 =~ "zuerst init"))
    end

    test "Klartext-Eintrag im Bund: Exit 5" do
      dir = tmp_area!("eintrag-klartext")
      opts = [tresor: tresor!(dir), security: security!(dir, "kanarien-klartext-eintrag")]
      kassette!(dir, "0001-get-x.json", "{}")

      {5, meldungen} = RisKassetten.run(["seal", dir], opts)

      assert Enum.any?(texts(meldungen), &(&1 =~ "kein Siegel"))
    end

    test "Repo-Ablehnung: seal/unseal in einem Git-Repo, nichts wird angefasst" do
      dir = tmp_area!("repo")
      opts = [tresor: tresor!(dir), security: security!(dir)]
      repo_dir = Path.join(__DIR__, "fixtures/replay")
      vorher = File.ls!(repo_dir)

      {1, meldungen} = RisKassetten.run(["seal", repo_dir], opts)
      assert Enum.any?(texts(meldungen), &(&1 =~ "Git-Repo"))
      assert File.ls!(repo_dir) == vorher

      {1, meldungen} = RisKassetten.run(["unseal", repo_dir], opts)
      assert Enum.any?(texts(meldungen), &(&1 =~ "Git-Repo"))

      assert RisKassetten.check_dir(System.tmp_dir!()) == :ok
      assert calls(dir, "tresor-calls", "open") == 0
    end

    test "ohne Tresor: Exit 3 auch beim seal" do
      dir = tmp_area!("seal-ohne-tresor")
      opts = [tresor: "/nicht/da", security: security!(dir)]
      kassette!(dir, "0001-get-x.json", "{}")

      {3, meldungen} = RisKassetten.run(["seal", dir], opts)

      assert Enum.any?(texts(meldungen), &(&1 =~ "komki-tresor nicht gefunden"))
    end

    test "verzeichnis fehlt: Exit 1" do
      dir = tmp_area!("dir-fehlt")

      {1, meldungen} = RisKassetten.run(["seal", Path.join(dir, "gibts-nicht")], [])

      assert Enum.any?(texts(meldungen), &(&1 =~ "Verzeichnis fehlt"))
    end
  end

  describe "status" do
    test "zaehlt, ohne tresor oder Schluesselbund zu fragen" do
      dir = tmp_area!("status")
      tresor = script!(dir, "komki-tresor", "touch #{dir}/tresor-marker; exit 0")
      security = script!(dir, "security", "touch #{dir}/security-marker; exit 0")
      kassette!(dir, "0001-get-x.json", "{}")
      File.write!(Path.join(dir, "0002-get-y.json.enc"), "rkt1-egal")

      {0, meldungen} = RisKassetten.run(["status", dir], tresor: tresor, security: security)

      assert Enum.any?(texts(meldungen), &(&1 =~ "1 Klartext-Kassette(n), 1 versiegelt"))
      refute File.exists?(Path.join(dir, "tresor-marker"))
      refute File.exists?(Path.join(dir, "security-marker"))
    end
  end

  describe "tresor-Protokoll" do
    test "Exit-Codes werden zu Gruenden (3/4/5/9)" do
      dir = tmp_area!("exit-codes")

      for {code, grund} <- [{3, :no_enclave}, {4, :refused}, {5, :invalid}, {9, {:failed, 9}}] do
        cmd = script!(dir, "tresor-#{code}", "read -r v; exit #{code}")
        assert {:error, ^grund} = RisKassetten.tresor_open("ktv1.x", "Test", tresor: cmd)
      end

      assert :ok = RisKassetten.tresor_check(script!(dir, "tresor-ok", "exit 0"))
      assert {:error, :no_enclave} = RisKassetten.tresor_check(script!(dir, "tresor-3", "exit 3"))
    end

    test "Klartext und Siegel gehen nie ueber argv" do
      dir = tmp_area!("argv")

      seal_cmd =
        script!(dir, "tresor-argv-seal", ~s(echo "$@" > #{dir}/argv; read -r v; echo ktv1.x))

      assert {:ok, _} = RisKassetten.tresor_seal("kanarienwert", tresor: seal_cmd)
      assert File.read!(Path.join(dir, "argv")) == "seal\n"

      open_cmd =
        script!(dir, "tresor-argv-open", ~s(echo "$@" > #{dir}/argv; read -r v; echo offen))

      assert {:ok, _} =
               RisKassetten.tresor_open("ktv1.siegelwert", "Grund fuer die Karte",
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
               RisKassetten.tresor_open("ktv1.x", "Test", tresor: cmd, open_timeout: 300)
    end
  end

  describe "Aufruf" do
    test "falsche Aufrufe: Exit 2 mit Usage" do
      for argv <- [[], ["nix"], ["seal"], ["seal", "a", "b"], ["init", "verzeichnis"]] do
        {2, meldungen} = RisKassetten.run(argv, [])
        assert Enum.any?(texts(meldungen), &(&1 =~ "Aufruf:"))
      end
    end

    test "--tresor-Flag haelt den Prozesspfad bis zur Ausfuehrung" do
      assert {:ok, {"seal", "/irgend/wo", [tresor: "/bin/tresor"]}} =
               RisKassetten.parse_cli(["seal", "/irgend/wo", "--tresor", "/bin/tresor"])

      assert {:ok, {"init", nil, [tresor: "/bin/tresor"]}} =
               RisKassetten.parse_cli(["init", "--tresor", "/bin/tresor"])
    end
  end

  defp flip(file, at) do
    blob = File.read!(file)
    pos = if at < 0, do: byte_size(blob) + at, else: at
    byte = :binary.at(blob, pos)

    File.write!(
      file,
      binary_part(blob, 0, pos) <>
        <<:erlang.bxor(byte, 0xFF)>> <> binary_part(blob, pos + 1, byte_size(blob) - pos - 1)
    )
  end
end
