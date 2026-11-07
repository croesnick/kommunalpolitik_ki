defmodule KomkiCli.ProcIdentityTest do
  @moduledoc """
  Ticket #164: `down` und `status` einer Basis behandeln nur Prozesse als
  eigene, die für genau diese Basis gestartet wurden. Attrappen tragen
  Prozessnamen und Basis-Anker in der ps-Kommandozeile (bzw. das Egress-Log
  als offene Datei); kein echter llama-server nötig.
  """

  use ExUnit.Case, async: true

  alias KomkiCli.{Channel, Connectors, Llama, Mediator, Proc, TestSupport}
  alias KomkiConnector.Manifest

  setup do
    mine = TestSupport.fixture_cfg(TestSupport.tmp_area!("komki-ident-mine"))
    other = TestSupport.fixture_cfg(TestSupport.tmp_area!("komki-ident-other"))

    for cfg <- [mine, other] do
      File.mkdir_p!(Path.join(cfg.base_dir, "tmp"))
      File.touch!(Connectors.egress_log_path(cfg))
    end

    %{mine: mine, other: other}
  end

  defp running?(pid), do: match?({_, 0}, System.cmd("/bin/kill", ["-0", Integer.to_string(pid)]))

  defp write_pid(path, pid), do: File.write!(path, Integer.to_string(pid) <> "\n")

  describe "Proc.pid_alive?/3" do
    test "Anker muss als ganzes Wort stehen (kein Teilpfad einer fremden Basis)", %{mine: mine} do
      anchor = Llama.key_path(mine)
      pid = TestSupport.spawn_fake("llama-server", "/vorn" <> anchor)

      try do
        refute Proc.pid_alive?(pid, "llama-server", anchor)
        assert Proc.pid_alive?(pid, "llama-server", "/vorn" <> anchor)
        assert Proc.pid_alive?(pid, "llama-server")
      after
        TestSupport.kill_fake(pid)
      end
    end
  end

  describe "llama" do
    test "fremder llama-server: down sendet kein Signal, Meldung 'fremd', status nicht running",
         %{mine: mine, other: other} do
      pid = TestSupport.spawn_fake("llama-server", Llama.key_path(other))
      write_pid(Llama.pidfile(mine), pid)

      try do
        assert {:error, status_msg} = Llama.status(mine)
        assert status_msg =~ "of this base"

        assert {:stale, msg} = Llama.down(mine)
        assert msg =~ "dieser Basis"
        assert msg =~ "kein Signal"
        refute File.exists?(Llama.pidfile(mine))
        assert running?(pid)
      after
        TestSupport.kill_fake(pid)
      end
    end

    test "eigener llama-server wird beendet", %{mine: mine} do
      pid = TestSupport.spawn_fake("llama-server", Llama.key_path(mine))
      write_pid(Llama.pidfile(mine), pid)

      try do
        assert {:running, ^pid} = Llama.status(mine)
        assert :ok = Llama.down(mine)
        refute running?(pid)
      after
        TestSupport.kill_fake(pid)
      end
    end
  end

  describe "Vermittler" do
    test "fremder Vermittler bleibt am Leben", %{mine: mine, other: other} do
      pid = TestSupport.spawn_fake("komki-mediator", Channel.socket_path(other))
      write_pid(Mediator.pidfile(mine), pid)

      try do
        assert {:error, status_msg} = Mediator.status(mine)
        assert status_msg =~ "of this base"

        assert {:stale, msg} = Mediator.down(mine)
        assert msg =~ "dieser Basis"
        assert running?(pid)
      after
        TestSupport.kill_fake(pid)
      end
    end

    test "eigener Vermittler wird beendet", %{mine: mine} do
      pid = TestSupport.spawn_fake("komki-mediator", Channel.socket_path(mine))
      write_pid(Mediator.pidfile(mine), pid)

      try do
        assert :ok = Mediator.down(mine)
        refute running?(pid)
      after
        TestSupport.kill_fake(pid)
      end
    end
  end

  describe "Connector" do
    test "fremder Connector bleibt am Leben, status meldet ihn nicht als laufend",
         %{mine: mine, other: other} do
      marker = Manifest.fetch!("web").binary
      pid = TestSupport.spawn_fake(marker, Manifest.socket_path(other.base_dir, "web"))
      write_pid(Connectors.pidfile(mine, "web"), pid)

      try do
        assert {"connector-web", {:error, status_msg}} =
                 List.keyfind(Connectors.status(mine), "connector-web", 0)

        assert status_msg =~ "of this base"

        assert {"connector-web", {:stale, msg}} =
                 List.keyfind(Connectors.down(mine), "connector-web", 0)

        assert msg =~ "dieser Basis"
        assert running?(pid)
      after
        TestSupport.kill_fake(pid)
      end
    end

    test "eigener Connector wird beendet", %{mine: mine} do
      marker = Manifest.fetch!("web").binary
      pid = TestSupport.spawn_fake(marker, Manifest.socket_path(mine.base_dir, "web"))
      write_pid(Connectors.pidfile(mine, "web"), pid)

      try do
        assert {"connector-web", :ok} = List.keyfind(Connectors.down(mine), "connector-web", 0)
        refute running?(pid)
      after
        TestSupport.kill_fake(pid)
      end
    end
  end

  describe "Egress (Anker: offenes Log, keine Argumente)" do
    test "Egress einer anderen Basis bleibt am Leben", %{mine: mine, other: other} do
      pid =
        TestSupport.spawn_fake("komki-egress", nil, open_file: Connectors.egress_log_path(other))

      write_pid(Connectors.egress_pidfile(mine), pid)

      try do
        assert {"egress", {:stale, msg}} = List.keyfind(Connectors.down(mine), "egress", 0)
        assert msg =~ "dieser Basis"
        assert running?(pid)
      after
        TestSupport.kill_fake(pid)
      end
    end

    test "eigener Egress wird beendet", %{mine: mine} do
      pid =
        TestSupport.spawn_fake("komki-egress", nil, open_file: Connectors.egress_log_path(mine))

      write_pid(Connectors.egress_pidfile(mine), pid)

      try do
        assert {"egress", :ok} = List.keyfind(Connectors.down(mine), "egress", 0)
        refute running?(pid)
      after
        TestSupport.kill_fake(pid)
      end
    end
  end
end
