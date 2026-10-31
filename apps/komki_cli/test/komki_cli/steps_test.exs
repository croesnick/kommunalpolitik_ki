defmodule KomkiCli.StepsTest do
  # write_pi_home ist die Testnaeht fuer alles, was komki dem pi-home
  # vorgibt: Provider-Modelle, Settings-Global und der Trust-Store. Der
  # Trust-Schluessel ist das Instanz-Root — pi's Trust-Suche laeuft vom
  # Session-cwd (die Arbeitsflaeche) die Elternkette hoch und muss dort
  # wie auch vom pi-home aus faendig werden.
  use ExUnit.Case, async: true

  alias KomkiCli.{Config, Denials, Proc, Steps, TestSupport}

  @denials_fixture Path.expand("../fixtures/denials/log-show.txt", __DIR__)

  describe "chain_base/2 (Ticket #251: Basis des Panes)" do
    @tag :tmp_dir
    test "die Basis kommt aus --base, auch ohne KOMKI_HOME im Pane", %{tmp_dir: dir} do
      assert Steps.chain_base(%{"base" => dir}, nil) == {:ok, Config.canonical(dir)}
    end

    @tag :tmp_dir
    test "KOMKI_HOME mit derselben Basis ist in Ordnung", %{tmp_dir: dir} do
      assert Steps.chain_base(%{"base" => dir}, dir) == {:ok, Config.canonical(dir)}
    end

    @tag :tmp_dir
    test "KOMKI_HOME einer anderen Instanz bricht ab", %{tmp_dir: dir} do
      other = Path.join(dir, "andere")

      assert {:error, reason, 2} = Steps.chain_base(%{"base" => dir}, other)
      assert reason =~ "Basis des Panes weicht ab"
    end

    test "ohne --base kein Rückfall auf die Standard-Basis" do
      assert {:error, reason, 2} = Steps.chain_base(%{}, nil)
      assert reason =~ "ohne --base"
    end
  end

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

  # Ticket #318: Ablage und Doctor-Checks des MTP-Drafters über die
  # öffentlichen Nahten Steps.place_drafter/2 und Steps.drafter_checks/2 —
  # hermetisch mit kleiner Datei und explizitem --drafter-from (das
  # Staging-Fallback ist host-abhängig und gehört zum echten Lauf).
  describe "MTP-Drafter (Ticket #318)" do
    @drafter_inhalt "kleiner test-drafter"
    @drafter_sha Base.encode16(:crypto.hash(:sha256, "kleiner test-drafter"), case: :lower)

    defp drafter_cfg(prefix, sha \\ nil) do
      cfg = TestSupport.fixture_cfg(TestSupport.tmp_area!(prefix))
      %{cfg | drafter_sha256: sha || @drafter_sha}
    end

    defp drafter_source(cfg) do
      source = Path.join(cfg.base_dir, "quelle-mtp.gguf")
      File.write!(source, @drafter_inhalt)
      source
    end

    test "place_drafter/2: --drafter-from, SHA verifiziert, Zeilen wie beim gguf" do
      cfg = drafter_cfg("komki-drafter-place")
      source = drafter_source(cfg)

      assert {:ok, [place, sha_line, ablage]} =
               Steps.place_drafter(cfg, %{"drafter-from" => source})

      assert place == "drafter:      " <> cfg.drafter_path
      assert sha_line == "drafter-sha256: " <> @drafter_sha <> " (pinned, verified)"
      assert ablage =~ ~r/drafter-ablage: (APFS-Klon|Kopie)/
      assert File.read!(cfg.drafter_path) == @drafter_inhalt
    end

    test "place_drafter/2: falscher SHA bricht ab, Kopie entfernt" do
      cfg = drafter_cfg("komki-drafter-falsch", String.duplicate("c", 64))
      source = drafter_source(cfg)

      assert {:error, reason, 2} = Steps.place_drafter(cfg, %{"drafter-from" => source})
      assert reason =~ "Drafter SHA256 mismatch"
      assert reason =~ "kopie entfernt"
      refute File.exists?(cfg.drafter_path)
    end

    test "place_drafter/2: nicht vorhandene Quelle ist ein Usage-Fehler" do
      cfg = drafter_cfg("komki-drafter-quelle")

      assert {:error, reason, 2} =
               Steps.place_drafter(cfg, %{"drafter-from" => "/gibt-es-nicht/mtp.gguf"})

      assert reason =~ "--drafter-from Pfad nicht gefunden"
    end

    test "drafter_checks/2: Präsenz im Start-Gate, Prüfsumme im vollen Doctor" do
      cfg = drafter_cfg("komki-drafter-checks")

      # Fehlende Datei: beide Scopes rot, mit dem Nachladeweg im Reason.
      for scope <- [:full, :profile_boot] do
        assert [%{ok: false, reason: reason}] = Steps.drafter_checks(cfg, scope)
        assert reason =~ "missing: " <> cfg.drafter_path
        assert reason =~ "'komki setup' lädt den MTP-Drafter nach"
      end

      File.mkdir_p!(Path.dirname(cfg.drafter_path))
      File.write!(cfg.drafter_path, @drafter_inhalt)

      assert [%{name: "drafter presence", ok: true, reason: presence_path}] =
               Steps.drafter_checks(cfg, :profile_boot)

      assert presence_path == cfg.drafter_path

      assert [%{name: "drafter sha256", ok: true, reason: @drafter_sha}] =
               Steps.drafter_checks(cfg, :full)

      # Andere Bytes: der volle Doctor meldet recorded gegen actual, das
      # Start-Gate bleibt grün (Praesenz genügt dort, wie beim gguf).
      verändert = %{cfg | drafter_sha256: String.duplicate("d", 64)}

      assert [%{name: "drafter sha256", ok: false, reason: reason}] =
               Steps.drafter_checks(verändert, :full)

      assert reason =~ "recorded " <> String.duplicate("d", 64)
      assert reason =~ "actual " <> @drafter_sha
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

  # Seit #132 liegt jeder Scratch unterhalb von runs/; denials/ ist ein
  # Nachbar. Ein Scratch im oder ueber dem Berichtsverzeichnis faellt damit
  # schon an scratch_for/2 (frueher eigener Guard, Ticket #125).
  describe "Scratch und Denial-Verzeichnis" do
    test "Scratch gleich, unter oder ueber denials/ wird abgewiesen" do
      cfg = TestSupport.fixture_cfg(TestSupport.tmp_area!("komki-steps-denials-guard"))
      denials = Denials.dir(cfg)
      File.mkdir_p!(Path.join(denials, "sub"))

      for scratch <- [denials, Path.join(denials, "sub"), cfg.base_dir] do
        assert {:error, _reason, 2} = Steps.scratch_for(%{"scratch" => scratch}, cfg.base_dir)
      end

      runs_scratch = Path.join([cfg.base_dir, "runs", "lauf"])
      File.mkdir_p!(runs_scratch)
      assert {:ok, _} = Steps.scratch_for(%{"scratch" => runs_scratch}, cfg.base_dir)
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
                 "connector-documents",
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
                 "connector-documents",
                 "egress",
                 "llama"
               ]

      assert Steps.start_order(%{cfg | vault_dir: nil, ris_mock_port: 4010}) ==
               [
                 "llama",
                 "egress",
                 "connector-documents",
                 "connector-ris",
                 "connector-web",
                 "mediator"
               ]
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
               [
                 "connector-web",
                 "connector-vault",
                 "connector-ris",
                 "connector-documents",
                 "egress"
               ]

      assert [
               {"connector-web", :ok},
               {"connector-vault", {:stale, _}},
               {"connector-ris", :ok},
               {"connector-documents", :already},
               {"egress", :ok}
             ] =
               connectors

      refute Enum.any?(pids, &Proc.pid_alive?(&1, ""))

      assert {:down, %{connectors: again}} = Steps.down_with(cfg)
      assert Enum.all?(again, fn {_name, state} -> state == :already end)
    end
  end
end
