defmodule KomkiCli.StepsTest do
  # write_pi_home ist die Testnaeht fuer alles, was komki dem pi-home
  # vorgibt: Provider-Modelle, Settings-Global und der Trust-Store. Der
  # Trust-Schluessel ist das Instanz-Root — pi's Trust-Suche laeuft vom
  # Session-cwd (die Arbeitsflaeche) die Elternkette hoch und muss dort
  # wie auch vom pi-home aus faendig werden.
  use ExUnit.Case, async: true

  alias KomkiCli.{Config, Proc, Steps, TestSupport}

  describe "write_pi_home/1" do
    test "Trust-Schlüssel ist das Instanz-Root (deckt arbeit und pi-home ab)" do
      cfg = TestSupport.fixture_cfg(TestSupport.tmp_area!("komki-steps"))

      Steps.write_pi_home(cfg)

      trust = cfg.pi_home |> Path.join(".pi/agent/trust.json") |> read_json()
      assert trust == %{Config.canonical(cfg.base_dir) => true}
    end

    test "Thinking per Default eingeklappt (hideThinkingBlock)" do
      cfg = TestSupport.fixture_cfg(TestSupport.tmp_area!("komki-steps"))

      Steps.write_pi_home(cfg)

      settings = cfg.pi_home |> Path.join(".pi/agent/settings.json") |> read_json()
      assert settings == %{"hideThinkingBlock" => true}
    end

    test "models.json zeigt auf den lokalen llama-Server" do
      cfg = TestSupport.fixture_cfg(TestSupport.tmp_area!("komki-steps"))

      Steps.write_pi_home(cfg)

      models = cfg.pi_home |> Path.join(".pi/agent/models.json") |> read_json()

      assert %{
               "providers" => %{
                 "pi-local" => %{
                   "baseUrl" => "http://127.0.0.1:" <> _,
                   "models" => [%{"id" => "local-model"}]
                 }
               }
             } = models
    end

    test "fd/rg landen als Kopien im agent-bin-Fundus (nil-tolerant)" do
      base = TestSupport.tmp_area!("komki-steps-tools")
      cfg = TestSupport.fixture_cfg(base)

      src_fd = Path.join(base, "fd-src")
      src_rg = Path.join(base, "rg-src")
      File.write!(src_fd, "fd-dummy")
      File.write!(src_rg, "rg-dummy")

      Steps.write_pi_home(%{cfg | fd_bin: src_fd, rg_bin: src_rg})

      bin = Path.join([cfg.pi_home, ".pi", "agent", "bin"])
      assert File.read!(Path.join(bin, "fd")) == "fd-dummy"
      assert File.read!(Path.join(bin, "rg")) == "rg-dummy"

      # Ueberschreiben trotz write-geschuetzter Altkopie (echte Binaries
      # behalten 555): init --force muss weiterhin funktionieren.
      File.chmod!(Path.join(bin, "fd"), 0o555)
      File.write!(src_fd, "fd-dummy-2")

      Steps.write_pi_home(%{cfg | fd_bin: src_fd, rg_bin: src_rg})

      assert File.read!(Path.join(bin, "fd")) == "fd-dummy-2"

      bare = TestSupport.fixture_cfg(TestSupport.tmp_area!("komki-steps-bare"))
      Steps.write_pi_home(%{bare | fd_bin: nil, rg_bin: nil})

      refute File.exists?(Path.join([bare.pi_home, ".pi", "agent", "bin", "fd"]))
    end
  end

  defp read_json(path), do: path |> File.read!() |> JSON.decode!()

  # Vermittler-Liveness-Gate (Review-Fund zur Vertragsluecke): run und
  # session muessen abbrechen, wenn der Vermittler tot oder das pidfile
  # stale ist — pi startet sonst mit `-e builtin:mcp` gegen eine tote
  # mcp.json. Muster wie das require_llama_up-Integrationsverhalten
  # (doctor_boot_test): klare Meldung, Exit 2, Handlungs-Hinweis.
  describe "run/1: --timeout (Ticket #133)" do
    test "0 und negative Werte werden vor jedem Check mit Exit 2 abgewiesen" do
      for t <- [0, -5] do
        assert {:error, msg, 2} = Steps.run(%{"prompt" => "x", "timeout" => t})
        assert msg =~ "--timeout"
      end
    end
  end

  describe "journal_check/1 (Ticket #139)" do
    setup do
      cfg = TestSupport.fixture_cfg(TestSupport.tmp_area!("komki-journal"))
      path = Path.join([cfg.base_dir, "mediator", "journal", "pdr.jsonl"])
      {:ok, cfg: cfg, path: path}
    end

    test "ohne Journal ok", %{cfg: cfg} do
      assert %{ok: true, reason: "noch kein Journal"} = Steps.journal_check(cfg)
    end

    @tag :chflags
    test "Journal ohne uappnd ist FAIL, mit uappnd ok", %{cfg: cfg, path: path} do
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, "")
      assert %{ok: false} = Steps.journal_check(cfg)

      {_, 0} = System.cmd("/usr/bin/chflags", ["uappnd", path])
      on_exit(fn -> System.cmd("/usr/bin/chflags", ["nouappnd", path]) end)
      assert %{ok: true, reason: "uappnd gesetzt"} = Steps.journal_check(cfg)
    end
  end

  describe "scratch_for/2 (Ticket #132: Scratch nur unter base/runs)" do
    setup do
      base = TestSupport.tmp_area!("komki-scratch")
      {:ok, base: base, runs: Config.canonical(Path.join(base, "runs"))}
    end

    test "Default liegt unter base/runs", %{base: base, runs: runs} do
      assert {:ok, scratch} = Steps.scratch_for(%{}, base)
      assert String.starts_with?(scratch, runs <> "/")
    end

    test "expliziter Pfad unter base/runs wird angenommen", %{base: base, runs: runs} do
      assert {:ok, scratch} = Steps.scratch_for(%{"scratch" => Path.join(runs, "x")}, base)
      assert scratch == Path.join(runs, "x")
    end

    test "Pfad außerhalb wird abgelehnt", %{base: base} do
      outside = TestSupport.tmp_area!("komki-scratch-outside")
      assert {:error, msg, 2} = Steps.scratch_for(%{"scratch" => outside}, base)
      assert msg =~ "unterhalb"
    end

    test "runs selbst und ..-Ausbruch werden abgelehnt", %{base: base, runs: runs} do
      assert {:error, _, 2} = Steps.scratch_for(%{"scratch" => runs}, base)
      assert {:error, _, 2} = Steps.scratch_for(%{"scratch" => Path.join(runs, "../x")}, base)
    end

    test "Symlink unter runs mit Ziel außerhalb wird abgelehnt", %{base: base, runs: runs} do
      outside = TestSupport.tmp_area!("komki-scratch-target")
      File.mkdir_p!(runs)
      link = Path.join(runs, "link")
      File.ln_s!(outside, link)
      assert {:error, _, 2} = Steps.scratch_for(%{"scratch" => link}, base)
    end
  end

  describe "require_mediator_up/1 (Liveness-Gate vor pi)" do
    test "kein pidfile, stiller Socket: Abbruch mit 'komki up'-Hinweis (Exit 2)" do
      cfg = med_gate_cfg("komki-steps-med")

      assert {:error, reason, 2} = Steps.require_mediator_up(cfg)
      assert reason =~ "komki-mediator nicht aktiv"
      assert reason =~ "'komki up' zuerst"
    end

    test "stale pidfile (toter Prozess): Abbruch statt pi gegen tote mcp.json (Exit 2)" do
      cfg = med_gate_cfg("komki-steps-med-stale")
      pidfile = Path.join([cfg.base_dir, "tmp", "komki-mediator.pid"])
      File.mkdir_p!(Path.dirname(pidfile))

      # Pid 99998 (macOS' hoechste normale Pid) existiert im Testumfeld nicht:
      # der Identitaetscheck verweigert die Zuordnung, status meldet stale.
      File.write!(pidfile, "99998\n")

      assert {:error, reason, 2} = Steps.require_mediator_up(cfg)
      assert reason =~ "stale pidfile"
      assert reason =~ "is not komki-mediator"
    end

    test "lebender eigener Prozess mit pidfile: Durchlass ({:ok, pid})" do
      cfg = med_gate_cfg("komki-steps-med-alive")

      # Eigener Prozess fuer den ps-Identitaetscheck: die Marker-Form im
      # sh-Argument taucht in der ps-Kommandozeile auf; Compound-Kommando
      # (statt einzelner Befehl) verhindert das sh-exec, das die Argzeile
      # durch den Kindprozess ersetzen wuerde.
      ps_marker = "komki-mediator"
      cmd = "while :; do sleep 1; done # " <> ps_marker
      port = Port.open({:spawn_executable, "/bin/sh"}, args: ["-c", cmd])
      {:os_pid, os_pid} = Port.info(port, :os_pid)

      pidfile = Path.join([cfg.base_dir, "tmp", "komki-mediator.pid"])
      File.mkdir_p!(Path.dirname(pidfile))
      File.write!(pidfile, to_string(os_pid) <> "\n")

      assert {:ok, ^os_pid} = Steps.require_mediator_up(cfg)

      # Aufraeumweg ueber die eigene Eskalations-Mechanik (TERM → KILL mit
      # Identitaetscheck): zugleich Regression fuer KomkiCli.Proc.kill_checked.
      assert :ok = Proc.kill_checked(os_pid, ps_marker)
    end
  end

  defp med_gate_cfg(prefix) do
    # Kein Token, kein Socket: healthz scheitert sicher (Ticket #143).
    TestSupport.fixture_cfg(TestSupport.tmp_area!(prefix))
  end

  describe "up/down-Reihenfolge (Ticket #146)" do
    test "start_order: llama, egress, Connectoren, Vermittler; stop_order umgekehrt" do
      cfg = TestSupport.fixture_cfg(TestSupport.tmp_area!("komki-order"))

      assert Steps.start_order(cfg) ==
               [
                 "llama",
                 "egress",
                 "connector-ris",
                 "connector-vault",
                 "connector-web",
                 "mediator"
               ]

      assert Steps.stop_order() ==
               [
                 "mediator",
                 "connector-web",
                 "connector-vault",
                 "connector-ris",
                 "egress",
                 "llama"
               ]

      assert Steps.start_order(%{cfg | vault_dir: nil, ris_mock_port: 4010}) ==
               ["llama", "egress", "connector-ris", "connector-web", "mediator"]
    end

    test "down_with/1: stoppt Egress und Connectoren per pidfile, Ergebnis in stop_order, idempotent" do
      cfg = TestSupport.fixture_cfg(TestSupport.tmp_area!("komki-down"))
      tmp = Path.join(cfg.base_dir, "tmp")
      File.mkdir_p!(tmp)

      # Marker-Prozesse wie im Liveness-Gate-Test: die ps-Kommandozeile
      # traegt den Escript-Namen, den der Identitaetscheck erwartet.
      pids =
        for {file, marker} <- [
              {"komki-egress.pid", "komki-egress"},
              {"connector-ris.pid", "komki-connector-ris"},
              {"connector-web.pid", "komki-connector-web"}
            ] do
          port =
            Port.open({:spawn_executable, "/bin/sh"},
              args: ["-c", "while :; do sleep 1; done # " <> marker]
            )

          {:os_pid, pid} = Port.info(port, :os_pid)
          File.write!(Path.join(tmp, file), Integer.to_string(pid) <> "\n")
          pid
        end

      # stale pidfile beim Vault-Connector: wird entfernt, nichts getoetet
      File.write!(Path.join(tmp, "connector-vault.pid"), "99998\n")

      assert {:down, %{mediator: :already, connectors: connectors, llama: :already}} =
               Steps.down_with(cfg)

      assert Enum.map(connectors, &elem(&1, 0)) ==
               ["connector-web", "connector-vault", "connector-ris", "egress"]

      assert [
               {"connector-web", :ok},
               {"connector-vault", {:stale, _}},
               {"connector-ris", :ok},
               {"egress", :ok}
             ] =
               connectors

      refute Enum.any?(pids, &Proc.pid_alive?(&1, ""))

      assert {:down, %{connectors: again}} = Steps.down_with(cfg)
      assert Enum.all?(again, fn {_name, state} -> state == :already end)
    end
  end
end
