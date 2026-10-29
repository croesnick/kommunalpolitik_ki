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
    test "Default: alle vier aktiv, Egress mit ris- und web-Port" do
      cfg = cfg()
      assert Enum.map(Connectors.enabled(cfg), & &1.id) == ["documents", "ris", "vault", "web"]

      assert Connectors.egress_ports(cfg) == [
               {49_531, "ris", ["risapi1.komuna.net:443"]},
               {49_532, "web", ["api.search.brave.com:443"]}
             ]
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

    test "egress_stdin: Format von komki-egress" do
      assert JSON.decode!(Connectors.egress_stdin(cfg())) == %{
               "ports" => %{
                 "49531" => %{"connector" => "ris", "allow" => ["risapi1.komuna.net:443"]},
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
               "https://risapi1.komuna.net/web/"
             ]
    end

    test "ris im Mock: kein Proxy, Basis-URL auf den Mock" do
      args = Connectors.connector_args(cfg(ris_mock_port: 4010), Manifest.fetch!("ris"))
      refute "--proxy" in args
      assert ["--base-url", "http://127.0.0.1:4010/"] == Enum.take(args, -2)
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
        Connectors.credentials_line(Manifest.fetch!("ris"), token, fn _ -> flunk("kein Abruf") end)

      assert JSON.decode!(line) == %{"KOMKI_CONNECTOR_TOKEN" => token}
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
      assert reason =~ "documents.sock"
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

      fakes =
        for {pidfile, marker} <-
              [{Connectors.egress_pidfile(cfg), "komki-egress"}] ++
                for(
                  id <- ["documents", "ris", "vault", "web"],
                  do: {Connectors.pidfile(cfg, id), Manifest.fetch!(id).binary}
                ) do
          # Compound-Kommando, damit der Marker in der ps-Zeile bleibt
          port =
            Port.open({:spawn_executable, "/bin/sh"},
              args: ["-c", "while :; do sleep 1; done # " <> marker]
            )

          {:os_pid, pid} = Port.info(port, :os_pid)
          File.write!(pidfile, Integer.to_string(pid) <> "\n")
          {pid, marker}
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
        for {pid, marker} <- fakes, do: Proc.kill_checked(pid, marker)
      end
    end
  end
end
