defmodule KomkiCli.StepsTest do
  # write_pi_home ist die Testnaeht fuer alles, was komki dem pi-home
  # vorgibt: Provider-Modelle, Settings-Global und der Trust-Store. Der
  # Trust-Schluessel ist das Instanz-Root — pi's Trust-Suche laeuft vom
  # Session-cwd (die Arbeitsflaeche) die Elternkette hoch und muss dort
  # wie auch vom pi-home aus faendig werden.
  use ExUnit.Case, async: true

  alias KomkiCli.{Config, Denials, Proc, Steps, TestSupport}

  @denials_fixture Path.expand("../fixtures/denials/log-show.txt", __DIR__)

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

  # Ticket #125: Naht um pi-Lauf, Zeitfenster und Denial-Capture. Kein
  # echtes llama/pi/log — pi_fun und capture_fun sind injiziert.
  describe "run_pi_with_capture/5" do
    test "pi laeuft vor dem Capture, Fenster wird uebergeben, Bericht geschrieben" do
      cfg = TestSupport.fixture_cfg(TestSupport.tmp_area!("komki-steps-denials"))
      scratch = Path.join([cfg.base_dir, "runs", "lauf-1"])
      test_pid = self()

      output =
        @denials_fixture
        |> File.read!()
        |> String.replace("/Users/alice/.local/share/komki", cfg.base_dir)

      pi_fun = fn _cfg, _scratch, _mode, _prompt ->
        send(test_pid, :pi_done)
        {:ok, "antwort"}
      end

      capture_fun = fn window, opts ->
        send(test_pid, {:capture, window, opts})

        Denials.capture(
          window,
          opts ++ [binary: "/bin/sh", runner: fn _argv -> {output, 0} end]
        )
      end

      assert {:run_ok, ^scratch, "antwort", summary} =
               Steps.run_pi_with_capture(cfg, scratch, :text, "hallo",
                 capture?: true,
                 drain_ms: 0,
                 pi_fun: pi_fun,
                 capture_fun: capture_fun
               )

      assert_receive :pi_done
      assert_receive {:capture, window, opts}

      assert %{status: "ok", report_path: report_path, error: nil} = summary
      assert report_path == Path.join("denials", Path.basename(report_path))
      refute report_path =~ cfg.base_dir
      refute report_path =~ System.user_home!()

      absolute_report = Path.join(cfg.base_dir, report_path)
      assert File.exists?(absolute_report)

      footer = Denials.footer(summary)
      refute footer =~ cfg.base_dir
      refute footer =~ System.user_home!()

      assert opts[:base_dir] == cfg.base_dir
      assert opts[:scratch] == scratch

      assert DateTime.compare(window.start, window.end) == :lt
      assert window.pre_roll_ms == 1_000
      assert window.drain_wait_ms == 0
      assert window.duration_ms >= 0

      report_json = absolute_report |> File.read!() |> JSON.decode!()
      assert report_json["schema"] == "komki-denials/1"
      assert report_json["run"]["mode"] == "text"
      assert report_json["run"]["pi_exit"] == 0
      assert is_list(report_json["denials"]) and report_json["denials"] != []

      report_raw = JSON.encode!(report_json)
      refute report_raw =~ System.user_home!()
      refute report_raw =~ cfg.base_dir
      refute report_raw =~ scratch
      assert report_json["epistemic_limit"] =~ "kein Konfinement-Beweis"
    end

    test "Capture laeuft auch im pi-Fehlerfall" do
      cfg = TestSupport.fixture_cfg(TestSupport.tmp_area!("komki-steps-denials-err"))
      scratch = Path.join([cfg.base_dir, "runs", "lauf-2"])
      test_pid = self()

      pi_fun = fn _cfg, _scratch, _mode, _prompt -> {:error, "pi kaputt", 7} end

      capture_fun = fn _window, _opts ->
        send(test_pid, :capture_ran)
        {:ok, ok_capture()}
      end

      assert {:run_error, ^scratch, "pi kaputt", 7, %{status: "ok"}} =
               Steps.run_pi_with_capture(cfg, scratch, :json, "hallo",
                 capture?: true,
                 drain_ms: 0,
                 pi_fun: pi_fun,
                 capture_fun: capture_fun
               )

      assert_receive :capture_ran
    end

    test "kein Capture ohne Flag" do
      cfg = TestSupport.fixture_cfg(TestSupport.tmp_area!("komki-steps-denials-off"))
      scratch = Path.join([cfg.base_dir, "runs", "lauf-3"])
      test_pid = self()

      result =
        Steps.run_pi_with_capture(cfg, scratch, :text, "hallo",
          pi_fun: fn _cfg, _scratch, _mode, _prompt -> {:ok, "antwort"} end,
          capture_fun: fn _window, _opts ->
            send(test_pid, :capture_ran)
            {:ok, ok_capture()}
          end
        )

      assert {:run_ok, ^scratch, "antwort", nil} = result
      refute_received :capture_ran
      refute File.exists?(Denials.dir(cfg))
    end

    test "Capture-Fehler bleibt als Fehler sichtbar" do
      cfg = TestSupport.fixture_cfg(TestSupport.tmp_area!("komki-steps-denials-fail"))
      scratch = Path.join([cfg.base_dir, "runs", "lauf-4"])

      assert {:run_ok, ^scratch, "antwort", summary} =
               Steps.run_pi_with_capture(cfg, scratch, :text, "hallo",
                 capture?: true,
                 drain_ms: 0,
                 pi_fun: fn _cfg, _scratch, _mode, _prompt -> {:ok, "antwort"} end,
                 capture_fun: fn _window, _opts -> {:error, "log fehlt"} end
               )

      assert summary == %{
               status: "capture_error",
               denials: [],
               report_path: nil,
               error: "log fehlt"
             }
    end

    test "Fehlerpfad wird vor dem Footer redigiert" do
      cfg = TestSupport.fixture_cfg(TestSupport.tmp_area!("komki-steps-denials-redact"))
      scratch = Path.join([cfg.base_dir, "runs", "lauf-5"])

      raw_error = "cannot read " <> Path.join(cfg.base_dir, "denials/report.json")

      assert {:run_ok, ^scratch, "antwort", summary} =
               Steps.run_pi_with_capture(cfg, scratch, :text, "hallo",
                 capture?: true,
                 drain_ms: 0,
                 pi_fun: fn _cfg, _scratch, _mode, _prompt -> {:ok, "antwort"} end,
                 capture_fun: fn _window, _opts -> {:error, raw_error} end
               )

      refute summary.error =~ cfg.base_dir
      refute summary.error =~ System.user_home!()
      assert summary.error =~ "<base>/<redacted>"

      footer = Denials.footer(summary)
      refute footer =~ cfg.base_dir
      refute footer =~ System.user_home!()
    end
  end

  describe "refuse_denials_scratch/2" do
    test "rejected Scratch gleich, unter und ueber dem Denial-Verzeichnis" do
      cfg = TestSupport.fixture_cfg(TestSupport.tmp_area!("komki-steps-denials-guard"))
      denials = Denials.dir(cfg)

      for scratch <- [
            denials,
            Path.join(denials, "sub"),
            cfg.base_dir,
            Path.dirname(cfg.base_dir)
          ] do
        assert {:error, reason, 2} =
                 Steps.refuse_denials_scratch(%{"scratch" => scratch}, cfg)

        refute reason =~ cfg.base_dir
      end
    end

    test "Scratch ausserhalb bleibt erlaubt" do
      cfg = TestSupport.fixture_cfg(TestSupport.tmp_area!("komki-steps-denials-guard-ok"))
      scratch = Path.join([cfg.base_dir, "runs", "lauf"])

      assert :ok = Steps.refuse_denials_scratch(%{"scratch" => scratch}, cfg)
    end
  end

  defp ok_capture do
    %{
      status: "ok",
      log_binary: "/usr/bin/log",
      argv: [],
      predicate: "",
      error: nil,
      matched: 0,
      parsed: 0,
      unparsed: 0,
      denials: [],
      redacted_count: 0
    }
  end

  defp med_gate_cfg(prefix) do
    %{TestSupport.fixture_cfg(TestSupport.tmp_area!(prefix)) | mediator_port: 1}
  end
end
