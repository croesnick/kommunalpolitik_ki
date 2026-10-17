defmodule KomkiCli.DenialsTest do
  # Kein echtes llama/pi/log: capture bekommt einen injizierten Runner bzw.
  # ein erfundenes Binary. Die Tests pinnen argv, Parsing, Redaktion und die
  # atomare append-only Persistenz.
  use ExUnit.Case, async: true

  import Bitwise

  alias KomkiCli.{Denials, TestSupport}

  @fixture Path.expand("../fixtures/denials/log-show.txt", __DIR__)

  setup do
    cfg = TestSupport.fixture_cfg(TestSupport.tmp_area!("komki-denials"))
    scratch = Path.join([cfg.base_dir, "runs", "2026-10-17T20-00-00Z"])
    %{cfg: cfg, scratch: scratch}
  end

  describe "show_args/1" do
    test "pinnt die exakte argv inklusive Predicate" do
      start = ~U[2026-10-17 20:00:00.000000Z]
      end_ = ~U[2026-10-17 20:00:05.123456Z]

      assert Denials.show_args(%{start: start, end: end_}) == [
               "/usr/bin/log",
               "show",
               "--style",
               "compact",
               "--timezone",
               "UTC",
               "--start",
               "2026-10-17 20:00:00+0000",
               "--end",
               "2026-10-17 20:00:06+0000",
               "--predicate",
               ~S|(process == "kernel" OR sender == "Sandbox") AND eventMessage CONTAINS "Sandbox:" AND eventMessage CONTAINS "deny("|
             ]
    end

    test "sekundengenau: Start abrunden, Ende aufrunden, keine Bruchteile" do
      start = ~U[2026-10-17 20:00:00.999999Z]
      end_ = ~U[2026-10-17 20:00:05.000001Z]

      argv = Denials.show_args(%{start: start, end: end_})
      start_arg = Enum.at(argv, Enum.find_index(argv, &(&1 == "--start")) + 1)
      end_arg = Enum.at(argv, Enum.find_index(argv, &(&1 == "--end")) + 1)

      assert start_arg == "2026-10-17 20:00:00+0000"
      assert end_arg == "2026-10-17 20:00:06+0000"

      # Live-Regression: `log show` scheitert an Bruchteilen (Exit 64).
      for timestamp <- [start_arg, end_arg] do
        refute String.contains?(timestamp, ".")
        assert timestamp =~ ~r/^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\+0000$/
      end
    end

    test "ganze Sekunden bleiben unveraendert" do
      start = ~U[2026-10-17 20:00:00.000000Z]
      end_ = ~U[2026-10-17 20:00:05.000000Z]

      argv = Denials.show_args(%{start: start, end: end_})
      start_arg = Enum.at(argv, Enum.find_index(argv, &(&1 == "--start")) + 1)
      end_arg = Enum.at(argv, Enum.find_index(argv, &(&1 == "--end")) + 1)

      assert start_arg == "2026-10-17 20:00:00+0000"
      assert end_arg == "2026-10-17 20:00:05+0000"
    end
  end

  describe "parse/1" do
    test "gruppiert Duplikate, behaelt Operation/Prozess/PID und zaehlt Unparsebares" do
      parsed = @fixture |> File.read!() |> Denials.parse()

      assert parsed.matched == 10
      assert parsed.parsed == 9
      assert parsed.unparsed == 1
      assert length(parsed.denials) == 8

      system =
        Enum.find(
          parsed.denials,
          &(&1.target == "/System/Library/Frameworks/CoreFoundation.framework")
        )

      assert system.occurrences == 3
      assert system.operation == "file-read-data"
      assert system.process == "logd_helper"
      assert system.pid == 68_001
      assert system.deny_count == 1
      assert system.logged_at == "2026-10-17T21:15:07.400Z"

      mach = Enum.find(parsed.denials, &(&1.operation == "mach-lookup"))
      assert mach.target == "com.apple.MTLCompilerService"

      sysctl = Enum.find(parsed.denials, &(&1.operation == "sysctl-read"))
      assert sysctl.target == "kern.osproductversion"

      spaced = Enum.find(parsed.denials, &String.contains?(&1.target, "My Documents"))
      assert spaced.target == "/Users/alice/My Documents/report.pdf"
    end

    test "Live-Format: Header ignoriert, duplicate report gruppiert, kein unparsed" do
      output = """
      Timestamp               Ty Process[PID:TID]
      2026-10-17 21:15:07.287 E  kernel[0:284972] (Sandbox) Sandbox: logd_helper(68001) deny(1) file-read-data /Users/alice/Library/Application Support/.burrito/expert_erts-15.2.7_0.1.11/lib/crypto-5.5.3/priv/lib/crypto.so
      2026-10-17 21:15:07.306 E  kernel[0:284972] (Sandbox) 1 duplicate report for Sandbox: logd_helper(68001) deny(1) file-read-data /Users/alice/Library/Application Support/.burrito/expert_erts-15.2.7_0.1.11/lib/crypto-5.5.3/priv/lib/crypto.so
      2026-10-17 21:15:07.306 E  kernel[0:284972] (Sandbox) Sandbox: logd_helper(68001) deny(1) file-read-data /Users/alice/projects/antragsthemen_meinungsbild/app/node_modules/@rolldown/binding-darwin-arm64/rolldown-binding.darwin-arm64.node
      """

      parsed = Denials.parse(output)

      assert parsed.matched == 3
      assert parsed.parsed == 3
      assert parsed.unparsed == 0
      assert length(parsed.denials) == 2

      crypto =
        Enum.find(
          parsed.denials,
          &String.ends_with?(&1.target, "/lib/crypto.so")
        )

      assert crypto.occurrences == 2

      assert crypto.target ==
               "/Users/alice/Library/Application Support/.burrito/expert_erts-15.2.7_0.1.11/lib/crypto-5.5.3/priv/lib/crypto.so"

      rolldown = Enum.find(parsed.denials, &(&1 != crypto))

      assert rolldown.target ==
               "/Users/alice/projects/antragsthemen_meinungsbild/app/node_modules/@rolldown/binding-darwin-arm64/rolldown-binding.darwin-arm64.node"
    end

    test "ein Nicht-Denial-Output ist unparseable, leerer Output ist ok" do
      assert %{parsed: 0, unparsed: 2, matched: 2} = Denials.parse("foo\nbar\n")
      assert %{parsed: 0, unparsed: 0, matched: 0} = Denials.parse("")
    end
  end

  describe "capture/2" do
    test "Fixture: Systempfade verbatim, Home/Base/Scratch redigiert", %{
      cfg: cfg,
      scratch: scratch
    } do
      output =
        @fixture
        |> File.read!()
        |> String.replace("/Users/alice/.local/share/komki", cfg.base_dir)

      {:ok, capture} =
        Denials.capture(window(),
          base_dir: cfg.base_dir,
          scratch: scratch,
          binary: existing_binary(),
          runner: fn _argv -> {output, 0} end
        )

      assert capture.status == "ok"
      assert capture.matched == 10
      assert capture.unparsed == 1
      assert capture.redacted_count == 5

      by_target = Map.new(capture.denials, &{&1.target, &1})

      assert Map.has_key?(by_target, "/System/Library/Frameworks/CoreFoundation.framework")
      assert Map.has_key?(by_target, "com.apple.MTLCompilerService")
      assert Map.has_key?(by_target, "kern.osproductversion")
      assert Map.has_key?(by_target, "<scratch>/<redacted>")
      assert Map.has_key?(by_target, "<base>/<redacted>")
      assert Map.has_key?(by_target, "<redacted-path>")

      refute Enum.any?(capture.denials, &String.contains?(&1.target, System.user_home!()))
      refute Enum.any?(capture.denials, &String.contains?(&1.target, cfg.base_dir))
      refute Enum.any?(capture.denials, &String.contains?(&1.target, scratch))
    end

    test "leerer Output ist ok mit null Denials" do
      assert {:ok, %{status: "ok", denials: [], matched: 0}} =
               Denials.capture(window(),
                 base_dir: "/tmp/komki-base",
                 binary: existing_binary(),
                 runner: fn _argv -> {"", 0} end
               )
    end

    test "Exit ungleich 0 ist error, Fehlermeldung redigiert, kein Bericht" do
      base = "/Users/alice/.local/share/komki"

      assert {:ok, capture} =
               Denials.capture(window(),
                 base_dir: base,
                 binary: existing_binary(),
                 runner: fn _argv -> {"log: failed /Users/alice/secret", 2} end
               )

      assert capture.status == "error"
      assert capture.denials == []
      assert capture.error =~ "log show exit 2"
      refute capture.error =~ "/Users/alice"
      assert capture.error =~ "<redacted-path>"
    end

    test "Timeout wird als timeout gemeldet" do
      assert {:ok, %{status: "timeout"}} =
               Denials.capture(window(),
                 base_dir: "/tmp/komki-base",
                 binary: existing_binary(),
                 timeout: 20,
                 runner: fn _argv ->
                   Process.sleep(200)
                   {"", 0}
                 end
               )
    end

    test "nicht parsebarer Output ist unparseable" do
      assert {:ok, %{status: "unparseable", denials: [], error: error}} =
               Denials.capture(window(),
                 base_dir: "/tmp/komki-base",
                 binary: existing_binary(),
                 runner: fn _argv -> {"nur eine Zeile ohne Denial\n", 0} end
               )

      assert error =~ "not parseable"
    end

    test "langer Fehler: Redaktion vor Kuerzung, kein Pfadrest" do
      home = System.user_home!()

      output =
        "log: " <>
          String.duplicate("x", 460) <>
          " " <>
          Path.join(home, "secret.txt") <>
          " " <>
          String.duplicate("y", 100)

      assert {:ok, %{status: "error", error: error}} =
               Denials.capture(window(),
                 base_dir: "/tmp/komki-base",
                 binary: existing_binary(),
                 runner: fn _argv -> {output, 2} end
               )

      refute error =~ home
      refute error =~ "secret.txt"
      assert error =~ "<redacted-path>"
      assert String.length(error) <= 500
    end

    test "fehlendes log-Binary ist unavailable" do
      missing = Path.join(TestSupport.tmp_area!("komki-denials-bin"), "log")

      assert {:ok, %{status: "unavailable", error: error}} =
               Denials.capture(window(), base_dir: "/tmp/komki-base", binary: missing)

      assert error =~ "log binary missing"
    end
  end

  describe "redact/3" do
    test "Verbatim, Platzhalter und unbekannte absolute Pfade", %{cfg: cfg, scratch: scratch} do
      home = System.user_home!()

      cases = [
        {"/System/Library/Frameworks/CoreFoundation.framework",
         "/System/Library/Frameworks/CoreFoundation.framework"},
        {"/usr/lib/dyld", "/usr/lib/dyld"},
        {"/bin/sh", "/bin/sh"},
        {"/sbin/launchd", "/sbin/launchd"},
        {"/Library/Apple/x", "/Library/Apple/x"},
        {"/opt/homebrew/lib/libomp.dylib", "/opt/homebrew/lib/libomp.dylib"},
        {"/private/etc/passwd", "/private/etc/passwd"},
        {"/private/var/db/x", "/private/var/db/x"},
        {"/private/var/run/mDNSResponder", "/private/var/run/mDNSResponder"},
        {"/private/var/select/x", "/private/var/select/x"},
        {"/dev/null", "/dev/null"},
        {"com.apple.MTLCompilerService", "com.apple.MTLCompilerService"},
        {"kern.osproductversion", "kern.osproductversion"},
        {"AGXDeviceUserClient", "AGXDeviceUserClient"},
        {"127.0.0.1:49524", "127.0.0.1:49524"},
        {Path.join([home, ".asdf", "installs", "nodejs", "24", "bin", "node"]),
         "<asdf>/<redacted>"},
        {Path.join([home, ".nvm", "versions", "node", "v24", "bin", "node"]), "<nvm>/<redacted>"},
        {Path.join([cfg.base_dir, "models", "gemma.gguf"]), "<base>/<redacted>"},
        {Path.join(scratch, "secret.txt"), "<scratch>/<redacted>"},
        {Path.join([home, "Documents", "notiz.md"]), "<redacted-path>"},
        {"/Users/fremd/notiz.md", "<redacted-path>"},
        {"/Volumes/Disk/notiz.md", "<redacted-path>"},
        {"/private/var/folders/xx/T/notiz.md", "<redacted-path>"},
        {"/tmp/notiz.md", "<redacted-path>"},
        {"/unbekannt/absolut/notiz.md", "<redacted-path>"},
        {"/Applications/My App.app", "/Applications/My App.app"}
      ]

      for {input, expected} <- cases do
        assert Denials.redact(input, cfg.base_dir, scratch) == expected, input
      end
    end

    test "eingebettete Pfade mit Leerzeichen, Quotes, =, Klammern und file://", %{
      cfg: cfg,
      scratch: scratch
    } do
      home = System.user_home!()
      path_with_space = Path.join(home, "My Documents/report.pdf")
      path = Path.join(home, "secret.txt")

      cases = [
        {"log: cannot open " <> path_with_space, "log: cannot open <redacted-path>"},
        {"open \"" <> path <> "\"", "open \"<redacted-path>\""},
        {"path=" <> path, "path=<redacted-path>"},
        {"(" <> path <> ")", "(<redacted-path>)"},
        {"file://" <> path, "file://<redacted-path>"},
        {"open /unbekannt/My Docs/report.pdf", "open <redacted-path>"},
        {"/unbekannt/My Docs/report.pdf", "<redacted-path>"}
      ]

      for {input, expected} <- cases do
        assert Denials.redact(input, cfg.base_dir, scratch) == expected, input
      end
    end

    test "eingebetteter Home-Pfad mit Leerzeichen in Fehlermeldung", %{
      cfg: cfg,
      scratch: scratch
    } do
      home = System.user_home!()

      message =
        "log: cannot open " <>
          Path.join(home, "My Documents/report.pdf") <> " (permission denied)"

      assert Denials.redact(message, cfg.base_dir, scratch) ==
               "log: cannot open <redacted-path> (permission denied)"
    end

    test "lange Fehlermeldung: Redaktion vor Kuerzung, kein Resttoken", %{
      cfg: cfg,
      scratch: scratch
    } do
      home = System.user_home!()

      message =
        String.duplicate("x", 480) <>
          " open " <> Path.join(home, "secret.txt") <> " " <> String.duplicate("y", 100)

      redacted = Denials.redact(message, cfg.base_dir, scratch)

      refute redacted =~ home
      refute redacted =~ "secret.txt"
      assert redacted =~ "<redacted-path>"
    end

    test "nutzerspezifische Praefixe schlagen System-Verbatim", %{scratch: _scratch} do
      base = "/opt/komki-base"
      scratch = "/Library/Scratch"

      assert Denials.redact("/opt/komki-base/models/x.gguf", base, scratch) ==
               "<base>/<redacted>"

      assert Denials.redact("/Library/Scratch/lauf/notiz.md", base, scratch) ==
               "<scratch>/<redacted>"
    end
  end

  describe "write_report/2" do
    test "Schema, Dateiname, Modus 0600, Verzeichnis 0700, kein tmp-Rest", %{cfg: cfg} do
      assert {:ok, path} = Denials.write_report(cfg, report())
      assert Path.dirname(path) == Denials.dir(cfg)
      assert Path.basename(path) =~ ~r/^\d{8}T\d{6}\.\d{6}Z-a{12}\.json$/
      assert band(File.stat!(path).mode, 0o777) == 0o600
      assert band(File.stat!(Denials.dir(cfg)).mode, 0o777) == 0o700

      report_json = path |> File.read!() |> JSON.decode!()
      assert report_json["schema"] == "komki-denials/1"
      assert Path.wildcard(Path.join(Denials.dir(cfg), ".tmp-*")) == []
    end

    test "Temp-Datei ist waehrend des Schreibens bereits 0600", %{cfg: cfg} do
      parent = self()

      assert {:ok, _path} =
               Denials.write_report(cfg, report(),
                 on_temp_open: fn tmp ->
                   send(parent, {:temp_mode, band(File.stat!(tmp).mode, 0o777)})
                 end
               )

      assert_receive {:temp_mode, 0o600}
    end

    test "simulierter Write-Fehler raeumt Temp-Datei und Ziel auf", %{cfg: cfg} do
      assert {:error, reason} =
               Denials.write_report(cfg, report(),
                 write_fun: fn _io, _content -> raise "simulierter Schreibfehler" end
               )

      assert reason =~ "simulierter Schreibfehler"
      assert Path.wildcard(Path.join(Denials.dir(cfg), ".tmp-*")) == []
      assert Path.wildcard(Path.join(Denials.dir(cfg), "*.json")) == []
    end

    test "parallele Writer: beide Berichte bleiben erhalten", %{cfg: cfg} do
      report = report()

      paths =
        1..2
        |> Enum.map(fn _ -> Task.async(fn -> Denials.write_report(cfg, report) end) end)
        |> Task.await_many(5_000)
        |> Enum.map(fn {:ok, path} -> path end)

      assert length(Enum.uniq(paths)) == 2
      assert length(Path.wildcard(Path.join(Denials.dir(cfg), "*.json"))) == 2
      assert Path.wildcard(Path.join(Denials.dir(cfg), ".tmp-*")) == []
    end

    test "append-only: gleicher created_at erzeugt eine zweite Datei, kein Ueberschreiben", %{
      cfg: cfg
    } do
      report = report()

      assert {:ok, first} = Denials.write_report(cfg, report)
      first_content = File.read!(first)

      assert {:ok, second} = Denials.write_report(cfg, report)
      refute first == second
      assert second =~ ~r/\.json$/
      assert Path.basename(second) =~ ~r/-a{12}-1\.json$/
      assert File.read!(first) == first_content
    end

    test "Schreibfehler hinterlaesst kein Zielartefakt", %{cfg: cfg} do
      File.write!(Denials.dir(cfg), "blockiert")

      assert {:error, _reason} = Denials.write_report(cfg, report())
      assert File.read!(Denials.dir(cfg)) == "blockiert"
    end
  end

  describe "footer/1" do
    test "ok mit Denials, none und Fehler" do
      denial = %{
        operation: "file-read-data",
        target: "<scratch>/<redacted>",
        occurrences: 3
      }

      summary = %{
        status: "ok",
        denials: [denial],
        report_path: "denials/2026.json",
        error: nil
      }

      footer = Denials.footer(summary)
      assert footer =~ "denials: 3 captured (1 unique) — report: denials/2026.json"
      assert footer =~ "file-read-data <scratch>/<redacted> ×3"

      assert Denials.footer(%{status: "ok", denials: [], report_path: "x"}) ==
               "denials: none in run window"

      assert Denials.footer(%{status: "error", denials: [], report_path: nil, error: "boom"}) ==
               "denials: capture FAILED (boom); no report"
    end

    test "mehr als fuenf Gruppen: Restzahl wird ausgewiesen" do
      denials =
        for n <- 1..7 do
          %{
            operation: "file-read-data",
            target: "/unbekannt/" <> Integer.to_string(n),
            occurrences: n
          }
        end

      footer = Denials.footer(%{status: "ok", denials: denials, report_path: "denials/x.json"})

      assert footer =~ "… weitere 2"
    end
  end

  defp window do
    %{
      start: ~U[2026-10-17 20:00:00.000000Z],
      end: ~U[2026-10-17 20:00:05.000000Z]
    }
  end

  defp existing_binary do
    if File.exists?("/bin/sh"), do: "/bin/sh", else: System.find_executable("sh")
  end

  defp report do
    now = DateTime.to_iso8601(DateTime.utc_now())

    %{
      "schema" => Denials.schema(),
      "created_at" => now,
      "window" => %{
        "start" => now,
        "end" => now,
        "duration_ms" => 12,
        "pre_roll_ms" => 1_000,
        "drain_wait_ms" => 500
      },
      "run" => %{
        "mode" => "text",
        "pi_exit" => 0,
        "scratch_hash" => String.duplicate("a", 64),
        "run_profile_sha256" => nil,
        "llama_profile_sha256" => nil
      },
      "capture" => %{
        "status" => "ok",
        "log_binary" => "/usr/bin/log",
        "argv" => [],
        "predicate" => "",
        "error" => nil,
        "matched" => 0,
        "parsed" => 0,
        "unparsed" => 0
      },
      "denials" => [],
      "redaction" => %{
        "policy" => "komki-denials-redact/1",
        "applied" => true,
        "redacted_count" => 0
      },
      "epistemic_limit" => "kein Konfinement-Beweis"
    }
  end
end
