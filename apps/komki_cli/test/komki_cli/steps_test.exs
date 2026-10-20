defmodule KomkiCli.StepsTest do
  # write_pi_home ist die Testnaeht fuer alles, was komki dem pi-home
  # vorgibt: Provider-Modelle, Settings-Global und der Trust-Store. Der
  # Trust-Schluessel ist das Instanz-Root — pi's Trust-Suche laeuft vom
  # Session-cwd (die Arbeitsflaeche) die Elternkette hoch und muss dort
  # wie auch vom pi-home aus faendig werden.
  use ExUnit.Case, async: true

  alias KomkiCli.{Config, Proc, Steps, TestSupport}

  describe "write_pi_home/1" do
    test "Trust-Schluessel ist das Instanz-Root (deckt arbeit und pi-home ab)" do
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

    test "Pfad ausserhalb wird abgelehnt", %{base: base} do
      outside = TestSupport.tmp_area!("komki-scratch-outside")
      assert {:error, msg, 2} = Steps.scratch_for(%{"scratch" => outside}, base)
      assert msg =~ "unterhalb"
    end

    test "runs selbst und ..-Ausbruch werden abgelehnt", %{base: base, runs: runs} do
      assert {:error, _, 2} = Steps.scratch_for(%{"scratch" => runs}, base)
      assert {:error, _, 2} = Steps.scratch_for(%{"scratch" => Path.join(runs, "../x")}, base)
    end

    test "Symlink unter runs mit Ziel ausserhalb wird abgelehnt", %{base: base, runs: runs} do
      outside = TestSupport.tmp_area!("komki-scratch-target")
      File.mkdir_p!(runs)
      link = Path.join(runs, "link")
      File.ln_s!(outside, link)
      assert {:error, _, 2} = Steps.scratch_for(%{"scratch" => link}, base)
    end
  end

  describe "require_mediator_up/1 (Liveness-Gate vor pi)" do
    test "kein pidfile, stiller Port: Abbruch mit 'komki up'-Hinweis (Exit 2)" do
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
    %{TestSupport.fixture_cfg(TestSupport.tmp_area!(prefix)) | mediator_port: 1}
  end
end
