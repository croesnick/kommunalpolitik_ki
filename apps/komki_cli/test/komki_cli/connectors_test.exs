defmodule KomkiCli.ConnectorsTest do
  @moduledoc """
  Auswahl, Start-Argumente, stdin-Bildung und Spawn-Zeile von Egress und
  Connectoren (Ticket #146) — ohne echte Connectoren.
  """

  use ExUnit.Case, async: true

  alias KomkiCli.{Connectors, Proc, TestSupport}
  alias KomkiConnector.Manifest

  @kanarie "kanarienwert-für-tests"

  defp cfg(overrides \\ []) do
    base = TestSupport.fixture_cfg(TestSupport.tmp_area!("komki-conn"))

    struct!(
      %{
        base
        | escript_bin: "/opt/erl/bin/escript",
          egress_bin: "/opt/komki/bin/komki-egress",
          connector_bins: %{
            "ris" => "/opt/komki/bin/komki-connector-ris",
            "web" => "/opt/komki/bin/komki-connector-web",
            "vault" => "/opt/komki/bin/komki-connector-vault",
            "documents" => "/opt/komki/bin/komki-connector-documents"
          }
      },
      overrides
    )
  end

  describe "Auswahl" do
    test "Default: alle aktiven (ohne ratsprojekte ohne Socket), Egress mit ris- und web-Port" do
      cfg = cfg()
      assert Enum.map(Connectors.enabled(cfg), & &1.id) == ["documents", "ris", "vault", "web"]

      assert Connectors.egress_ports(cfg) == [
               {49_531, "ris", ["risapi3.komuna.net:443"]},
               {49_532, "web", ["api.search.brave.com:443"]}
             ]
    end

    test "DURCHSTICH #409: ratsprojekte nur mit gesetztem Socket aktiv" do
      cfg = cfg(ratsprojekte_socket: "/tmp/hub.sock")

      assert Enum.map(Connectors.enabled(cfg), & &1.id) == [
               "documents",
               "ratsprojekte",
               "ris",
               "vault",
               "web"
             ]

      assert Connectors.connector_args(cfg, Manifest.fetch!("ratsprojekte")) ==
               [
                 "--socket",
                 Path.join([cfg.base_dir, "run", "connectors", "ratsprojekte.sock"]),
                 "--hub-socket",
                 "/tmp/hub.sock"
               ]
    end

    test "#419: ratsprojekte mit Stand-Datei allein aktiv, nur --stand" do
      cfg = cfg(ratsprojekte_stand: "/tmp/hub/stand.json")

      assert "ratsprojekte" in Enum.map(Connectors.enabled(cfg), & &1.id)

      assert Connectors.connector_args(cfg, Manifest.fetch!("ratsprojekte")) ==
               [
                 "--socket",
                 Path.join([cfg.base_dir, "run", "connectors", "ratsprojekte.sock"]),
                 "--stand",
                 "/tmp/hub/stand.json"
               ]
    end

    test "#419: nur Stand lesen braucht kein Hub-Token" do
      manifest = Manifest.fetch!("ratsprojekte")

      assert Connectors.needed_credentials(cfg(ratsprojekte_stand: "/x"), manifest).credentials ==
               %{}

      assert Connectors.needed_credentials(cfg(ratsprojekte_socket: "/tmp/hub.sock"), manifest).credentials ==
               %{"KOMKI_HUB_TOKEN" => "ratsprojekte-hub-token"}
    end

    test "vault_dir nil: Vault-Connector startet nicht" do
      assert Enum.map(Connectors.enabled(cfg(vault_dir: nil)), & &1.id) == [
               "documents",
               "ris",
               "web"
             ]
    end

    test "RIS-Mock: direkter Port, kein Egress-Port für ris" do
      cfg = cfg(ris_mock_port: 4010)
      assert Connectors.upstream(cfg, Manifest.fetch!("ris")) == {:direct, 4010}
      assert [{49_532, "web", _}] = Connectors.egress_ports(cfg)
    end

    test "Web-Mock: direkter Port, kein Egress-Port für web" do
      cfg = cfg(web_mock_port: 4020)
      assert Connectors.upstream(cfg, Manifest.fetch!("web")) == {:direct, 4020}
      assert [{49_531, "ris", _}] = Connectors.egress_ports(cfg)

      refute Connectors.egress_needed?(cfg(ris_mock_port: 4010, web_mock_port: 4020))
    end

    test "egress_stdin: Format von komki-egress" do
      assert JSON.decode!(Connectors.egress_stdin(cfg())) == %{
               "ports" => %{
                 "49531" => %{"connector" => "ris", "allow" => ["risapi3.komuna.net:443"]},
                 "49532" => %{"connector" => "web", "allow" => ["api.search.brave.com:443"]}
               }
             }
    end
  end

  describe "Start-Argumente (CONTRACT.md §4)" do
    test "ris: Socket, Proxy, echte Basis-URL" do
      cfg = cfg()

      assert Connectors.connector_args(cfg, Manifest.fetch!("ris")) == [
               "--socket",
               Path.join(cfg.base_dir, "run/connectors/ris.sock"),
               "--proxy",
               "127.0.0.1:49531",
               "--base-url",
               "https://risapi3.komuna.net/web/"
             ]
    end

    test "ris im Mock: kein Proxy, Basis-URL auf den Mock" do
      args = Connectors.connector_args(cfg(ris_mock_port: 4010), Manifest.fetch!("ris"))
      refute "--proxy" in args
      assert ["--base-url", "http://127.0.0.1:4010/"] == Enum.take(args, -2)
    end

    test "web im Mock: kein Proxy, Basis-URL auf den Mock, auch in der Spawn-Zeile von up" do
      cfg = cfg(web_mock_port: 4020)
      args = Connectors.connector_args(cfg, Manifest.fetch!("web"))

      assert args == [
               "--socket",
               Path.join(cfg.base_dir, "run/connectors/web.sock"),
               "--base-url",
               "http://127.0.0.1:4020/"
             ]

      spawn =
        Connectors.spawn_line(
          cfg,
          Connectors.profile_path(cfg, "web"),
          "/opt/komki/bin/komki-connector-web",
          args,
          Connectors.log_path(cfg, "web")
        )

      assert spawn =~ "--base-url"
      assert spawn =~ "http://127.0.0.1:4020/"
      refute spawn =~ "--proxy"
    end

    test "vault: --vault-dir, web: --proxy" do
      cfg = cfg()

      assert ["--vault-dir", cfg.vault_dir] ==
               Enum.take(Connectors.connector_args(cfg, Manifest.fetch!("vault")), -2)

      assert ["--proxy", "127.0.0.1:49532"] ==
               Enum.take(Connectors.connector_args(cfg, Manifest.fetch!("web")), -2)
    end

    test "Credentials nur in der stdin-Zeile, nie in argv oder Spawn-Zeile" do
      cfg = cfg()
      web = Manifest.fetch!("web")
      fetch = fn "brave-search-api" -> {:ok, @kanarie} end

      token = Sidecar.Token.generate()
      {line, missing} = Connectors.credentials_line(web, token, fetch)

      assert JSON.decode!(line) == %{
               "BRAVE_API_KEY" => @kanarie,
               "KOMKI_CONNECTOR_TOKEN" => token
             }

      assert String.ends_with?(line, "\n")
      assert missing == []

      args = Connectors.connector_args(cfg, web)

      spawn =
        Connectors.spawn_line(
          cfg,
          Connectors.profile_path(cfg, "web"),
          "/opt/komki/bin/komki-connector-web",
          args,
          Connectors.log_path(cfg, "web")
        )

      refute Enum.any?(args, &(&1 =~ @kanarie))
      refute spawn =~ @kanarie
      refute spawn =~ "BRAVE_API_KEY"
      refute spawn =~ token
    end

    test "fehlendes Credential: nur das Token und der Name (nie ein Wert) in missing" do
      token = Sidecar.Token.generate()

      {line, missing} =
        Connectors.credentials_line(Manifest.fetch!("web"), token, fn _ -> {:error, :missing} end)

      assert JSON.decode!(line) == %{"KOMKI_CONNECTOR_TOKEN" => token}
      assert missing == [{"BRAVE_API_KEY", :missing}]

      {line, []} =
        Connectors.credentials_line(Manifest.fetch!("vault"), token, fn _ ->
          flunk("kein Abruf")
        end)

      assert JSON.decode!(line) == %{"KOMKI_CONNECTOR_TOKEN" => token}
    end

    # Regression #496: Im Web-Mock spricht der Connector im Klartext mit
    # http://127.0.0.1:<mock-port>/ — ein Port, den jeder lokale Prozess
    # binden kann. Vor dem Fix stand in dieser stdin-Zeile der echte,
    # per Touch ID entsiegelte Brave-Schluessel (Abruf ueber fetch); nach
    # dem Fix provisioniert der Launcher den synthetischen Test-Key und
    # oeffnet das Siegel gar nicht.
    test "#496: Web-Mock provisioniert den synthetischen Test-Key, das Siegel bleibt zu" do
      cfg = cfg(web_mock_port: 4020)
      web = Manifest.fetch!("web")
      token = Sidecar.Token.generate()

      assert ["--base-url", "http://127.0.0.1:4020/"] ==
               Enum.take(Connectors.connector_args(cfg, web), -2)

      assert Connectors.synthetic_credentials(cfg, web) == %{
               "BRAVE_API_KEY" => Connectors.mock_web_key()
             }

      {line, missing} =
        Connectors.credentials_line(
          web,
          token,
          fn _ -> flunk("kein Abruf des echten Schluessels") end,
          Connectors.synthetic_credentials(cfg, web)
        )

      assert JSON.decode!(line) == %{
               "BRAVE_API_KEY" => Connectors.mock_web_key(),
               "KOMKI_CONNECTOR_TOKEN" => token
             }

      assert missing == []
      refute line =~ "brave-search-api"
    end

    test "#496: ohne Web-Mock bleibt es beim echten Schluessel, andere Connector ohne Synthetik" do
      web = Manifest.fetch!("web")

      assert Connectors.synthetic_credentials(cfg(), web) == %{}

      {line, []} =
        Connectors.credentials_line(web, Sidecar.Token.generate(), fn
          "brave-search-api" -> {:ok, @kanarie}
        end)

      assert JSON.decode!(line)["BRAVE_API_KEY"] == @kanarie

      # Auch mit Mock-Ports: Connectoren ohne Mock-Zugang bleiben ohne Synthetik.
      assert Connectors.synthetic_credentials(
               cfg(ris_mock_port: 4010, web_mock_port: 4020),
               Manifest.fetch!("vault")
             ) == %{}
    end

    # #148 as #496: against the RIS mock the stdin line carries the mock
    # seed's synthetic account; the seal of the real RIS login stays shut.
    test "#148: RIS-Mock provisioniert den synthetischen Zugang, das Siegel bleibt zu" do
      ris = Manifest.fetch!("ris")
      token = Sidecar.Token.generate()
      synthetic = Connectors.synthetic_credentials(cfg(ris_mock_port: 4010), ris)

      assert synthetic == %{"RIS_ZUGANG" => Connectors.mock_ris_zugang()}

      {line, []} =
        Connectors.credentials_line(
          ris,
          token,
          fn _ -> flunk("kein Abruf des echten Zugangs") end,
          synthetic
        )

      assert %{"login" => "ratsmitglied@komki.example"} =
               line |> JSON.decode!() |> Map.fetch!("RIS_ZUGANG") |> JSON.decode!()

      # Without the mock: the real login from the keychain entry ris-zugang.
      assert Connectors.synthetic_credentials(cfg(), ris) == %{}

      {line, []} =
        Connectors.credentials_line(ris, token, fn "ris-zugang" -> {:ok, @kanarie} end)

      assert JSON.decode!(line)["RIS_ZUGANG"] == @kanarie
    end

    # The synthetic account must match the mock's seed, or the sign-in against
    # the mock fails without any test noticing (review of #148).
    test "#148: synthetischer Zugang passt zum account des RIS-Mock-Seeds" do
      seed =
        "../../../komki_mock/priv/seeds/ris/default.json"
        |> Path.expand(__DIR__)
        |> File.read!()
        |> JSON.decode!()

      assert JSON.decode!(Connectors.mock_ris_zugang()) ==
               Map.take(seed["account"], ["login", "password"])
    end

    test "#148: Warnungen aus dem Start-Log erscheinen bei komki up" do
      log = Path.join(TestSupport.tmp_area!("komki-start-log"), "connector-ris.log")

      File.write!(log, """
      08:00:07.307 [warning] RIS-Anmeldung fehlgeschlagen: RIS lehnt die Anmeldung ab
      08:00:07.313 [info] sidecar komki-ris/2 listening on /tmp/x/ris.sock
      """)

      assert Connectors.start_warnings(Manifest.fetch!("ris"), log) == [
               "ris: RIS-Anmeldung fehlgeschlagen: RIS lehnt die Anmeldung ab"
             ]

      assert Connectors.start_warnings(Manifest.fetch!("ris"), log <> ".fehlt") == []
    end

    test "#148: ohne RIS-Zugang startet der RIS-Connector als Gast, ohne Warnung" do
      {line, missing} =
        Connectors.credentials_line(Manifest.fetch!("ris"), "t", fn _ -> {:error, :missing} end)

      assert JSON.decode!(line) == %{"KOMKI_CONNECTOR_TOKEN" => "t"}
      assert missing == [{"RIS_ZUGANG", :missing}]
    end

    test "Spawn-Zeile: env -i, sandbox-exec mit Profil, escript, stdin durchgereicht" do
      cfg = cfg()
      profile = Connectors.profile_path(cfg, "ris")

      line =
        Connectors.spawn_line(
          cfg,
          profile,
          "/opt/komki/bin/komki-connector-ris",
          ["--socket", "/s"],
          "/l.log"
        )

      assert line ==
               "exec 3<&0; nohup '/usr/bin/env' '-i' 'HOME=" <>
                 cfg.base_dir <>
                 "/run' 'PATH=/usr/bin:/bin' 'LANG=C' '" <>
                 cfg.sandbox_exec <>
                 "' '-f' '" <>
                 profile <>
                 "' '/opt/erl/bin/escript' '/opt/komki/bin/komki-connector-ris' '--socket' '/s' 0<&3 3<&- > '/l.log' 2>&1 & echo $!"
    end
  end

  describe "Socket-Pfadlaenge (103 Byte)" do
    test "kurze Basis ok, lange Basis abgelehnt" do
      assert :ok = Connectors.socket_length("/tmp/komki")
      long = "/tmp/" <> String.duplicate("x", 80)
      assert {:error, reason} = Connectors.socket_length(long)
      # DURCHSTICH #409: ratsprojekte ist der laengste Connector-Name
      assert reason =~ "ratsprojekte.sock"
    end
  end

  describe "Proc.spawn_detached/3 (stdin-Uebergabe)" do
    test "Zeile kommt per stdin an, danach EOF; nichts davon in der Kommandozeile" do
      dir = TestSupport.tmp_area!("komki-spawn")
      out = Path.join(dir, "stdin.txt")
      log = Path.join(dir, "log")

      line = Proc.spawn_line("/bin/sh", ["-c", Proc.quote_bin("cat > " <> out)], log, "0<&0")
      assert {:ok, pid} = Proc.spawn_detached(line, ~s({"K": "#{@kanarie}"}\n), "/")

      # cat endet erst mit EOF: beweist, dass komki stdin geschlossen hat
      assert wait_until(fn -> not Proc.pid_alive?(pid, "") end)
      assert File.read!(out) == ~s({"K": "#{@kanarie}"}\n)
      refute line =~ @kanarie
    end
  end

  describe "Reihenfolge" do
    test "Start: egress vor den Connectoren; Stopp: Connectoren rückwärts, dann egress" do
      assert Connectors.start_order(cfg()) == [
               "egress",
               "connector-documents",
               "connector-ris",
               "connector-vault",
               "connector-web"
             ]

      assert Connectors.start_order(cfg(vault_dir: nil)) == [
               "egress",
               "connector-documents",
               "connector-ris",
               "connector-web"
             ]

      assert Connectors.stop_order() == [
               "connector-web",
               "connector-vault",
               "connector-ris",
               "connector-ratsprojekte",
               "connector-documents",
               "egress"
             ]
    end
  end

  defp wait_until(fun, tries \\ 50) do
    cond do
      fun.() -> true
      tries == 0 -> false
      true -> Process.sleep(100) && wait_until(fun, tries - 1)
    end
  end

  describe "up/2 bei laufenden Komponenten" do
    # Regression: up loeschte den Socket eines laufenden Connectors, bevor es
    # merkte, dass er laeuft; danach galt er als "running", war aber
    # unerreichbar (enoent in komki session nach komki run).
    test "laufende Connectoren behalten Socket und gelten als bereits gestartet" do
      cfg = cfg()
      Connectors.ensure_run_dirs!(cfg)
      File.mkdir_p!(Path.join(cfg.base_dir, "tmp"))

      File.touch!(Connectors.egress_log_path(cfg))

      fakes =
        for {pidfile, marker, anchor, opts} <-
              [
                {Connectors.egress_pidfile(cfg), "komki-egress", nil,
                 [open_file: Connectors.egress_log_path(cfg)]}
              ] ++
                for(
                  id <- ["documents", "ris", "vault", "web"],
                  do:
                    {Connectors.pidfile(cfg, id), Manifest.fetch!(id).binary,
                     Manifest.socket_path(cfg.base_dir, id), []}
                ) do
          pid = TestSupport.spawn_fake(marker, anchor, opts)
          File.write!(pidfile, Integer.to_string(pid) <> "\n")
          {pid, marker, anchor, opts}
        end

      sockets =
        for id <- ["documents", "ris", "vault", "web"], do: Manifest.socket_path(cfg.base_dir, id)

      Enum.each(sockets, &File.write!(&1, ""))
      # Laufende Connectoren dieser Version haben ihr Token (sonst Neustart).
      Enum.each(sockets, &Sidecar.Token.provision!/1)

      try do
        assert {:ok, entries} = Connectors.up(cfg, fetch: fn _ -> {:error, :missing} end)
        assert Enum.all?(entries, fn {_name, state} -> match?({:already, _}, state) end)
        assert Enum.all?(sockets, &File.exists?/1)
      after
        for {pid, _, _, _} <- fakes, do: TestSupport.kill_fake(pid)
      end
    end
  end

  describe "ensure_run_dirs!/1: Modus-Haertung des Dokumenten-Stores" do
    # Regression F30/#498: Der Dokumenten-Store der Raumdokumente entstand
    # mit umask-Default (0755 unter 022), waehrend run/ und connectors/ zwei
    # Zeilen darueber auf 0700 forciert werden. Auf einem Multi-User-Host mit
    # durchquerbarer Basis las jedes lokale Konto die Fraktionsraum-Dokumente
    # direkt, ohne Gate und Connector. Der rote Lauf vor dem Fix unter
    # Standard-umask zeigte 0755 statt 0700.
    test "Store und Elternverzeichnis entstehen mit 0700 wie run/ und connectors/" do
      cfg = cfg()
      :ok = Connectors.ensure_run_dirs!(cfg)

      documents = Connectors.documents_dir(cfg)

      for dir <- [Connectors.run_dir(cfg), Connectors.connectors_dir(cfg)] do
        assert mode(dir) == 0o700
      end

      assert mode(Path.dirname(documents)) == 0o700
      assert mode(documents) == 0o700
    end

    test "zu offene Rechte vorhandener Verzeichnisse werden korrigiert" do
      cfg = cfg()
      documents = Connectors.documents_dir(cfg)

      File.mkdir_p!(documents)
      File.chmod!(Path.dirname(documents), 0o755)
      File.chmod!(documents, 0o755)

      :ok = Connectors.ensure_run_dirs!(cfg)

      assert mode(Path.dirname(documents)) == 0o700
      assert mode(documents) == 0o700
    end
  end

  defp mode(path) do
    {:ok, stat} = File.stat(path)
    Bitwise.band(stat.mode, 0o777)
  end
end
