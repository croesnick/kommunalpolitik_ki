defmodule KomkiCli.CLITest do
  # KOMKI_HOME ist eine globale Umgebung; keine parallelen Module (Race).
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias KomkiCli.{CLI, TestSupport}

  setup do
    home = TestSupport.tmp_area!("komki-cli")
    System.put_env("KOMKI_HOME", home)

    on_exit(fn -> System.delete_env("KOMKI_HOME") end)
    {:ok, home: home}
  end

  describe "usage-Disziplin (Exit 2, keine Seiteneffekte)" do
    test "unbekannter Befehl (optimus: unrecognized arguments)" do
      {out, 2} = CLI.run(["definitiv-nicht-ein-befehl"])
      assert out =~ "unrecognized arguments"
    end

    test "leeres argv" do
      {out, 2} = CLI.run([])
      assert out =~ "no command given"
    end

    test "run ohne PROMPT (optimus: missing required arguments)" do
      {out, 2} = CLI.run(["run"])
      assert out =~ "missing required arguments: PROMPT"
    end

    test "run mit invalidem --mode verweigert (Exit 2)" do
      home = System.get_env("KOMKI_HOME")
      {out, 2} = CLI.run(["run", "x", "--mode", "bogus"])
      assert out =~ "invalid --mode"
      # config kann bei Usage-Fehlern nicht erzeugt werden
      refute File.exists?(Path.join(home, "config.json"))
    end

    test "init mit FAKE-GGUF-Quelle bricht ab (SHA-Gate, Exit 2, Kopie entfernt)" do
      home = System.get_env("KOMKI_HOME")
      fake = Path.join(home, "fake.gguf")
      File.write!(fake, "definitely-not-a-gguf")

      {out, 2} = CLI.run(["init", "--gguf-from", fake])

      # Refusal-Vertrag ist umgebungsagnostisch: Mit vollstaendigen Werkzeugen
      # greift das SHA-Gate; ohne sie (CI-Renner) das Preflight noch davor.
      # Beides ist dieselbe Verweigerung: Exit 2, keine Seiteneffekte.
      assert out =~ "SHA256 mismatch" or out =~ "Werkzeug nicht entdeckt"

      # Nicht als brauchbar hingestellt: Kopie entfernt, keine config geschrieben
      refute File.exists?(Path.join([home, "models", "gemma-4-26B-A4B-it-UD-Q4_K_XL.gguf"]))
      refute File.exists?(Path.join(home, "config.json"))
    end

    test "version kommt durch" do
      {out, 0} = CLI.run(["version"])
      assert out =~ "komki "
    end

    # Ticket #318: --drafter-from ist das Pendant zu --gguf-from (vorhandene
    # Drafter-Datei statt Download).
    test "setup/init --help nennen --drafter-from" do
      {setup_out, 0} = CLI.run(["setup", "--help"])
      assert setup_out =~ "--drafter-from"

      {init_out, 0} = CLI.run(["init", "--help"])
      assert init_out =~ "--drafter-from"
    end

    test "run --help nennt --capture-denials" do
      {out, 0} = CLI.run(["run", "--help"])
      assert out =~ "--capture-denials"
    end

    test "--help druckt usage inkl. session (kein stummes 0)" do
      {out, 0} = CLI.run(["--help"])
      assert out =~ "USAGE:"
      assert out =~ "init"
      assert out =~ "run"
      assert out =~ "session"
    end

    test "session ohne config verweigert (Exit 2, kein tmux-Start)" do
      {out, 2} = CLI.run(["session"])
      assert out =~ "config"
    end

    test "session-chain ohne --base verweigert (Exit 2, Ticket #251)" do
      {out, 2} = CLI.run(["session-chain"])
      assert out =~ "ohne --base"
    end

    test "session-chain ohne config verweigert (Exit 2)" do
      {out, 2} = CLI.run(["session-chain", "--base", System.get_env("KOMKI_HOME")])
      assert out =~ "config"
    end
  end

  describe "Konfig-Guard" do
    test "init ohne --force verweigert Ueberschreiben (Exit 2)" do
      home = System.get_env("KOMKI_HOME")
      File.write!(Path.join(home, "config.json"), "{}")

      {out, 2} = CLI.run(["init"])
      assert out =~ "bereits vorhanden"
      assert out =~ "--force"
    end
  end

  # Farb-Vertragsnaht (Ticket #75): unter Burrito erzwingt der Wrapper
  # ansi_enabled und piped stdout (Regression #234) — _IS_TTY steuert.
  # IO.ANSI.enabled?/0 allein wuerde unter der Binary auch beim Pipen
  # Farbcodes in Dateien schreiben.
  describe "Farb-Gate (_IS_TTY, Burrito-Kontext)" do
    test "_IS_TTY=0: Fehler-Zeilen ohne ANSI-Sequenzen (piped unter Burrito)" do
      System.put_env("_IS_TTY", "0")
      on_exit(fn -> System.delete_env("_IS_TTY") end)

      {out, 2} = CLI.run(["doctor"])

      refute out =~ "\e["
    end

    test "_IS_TTY=1: Fehler-Zeilen farbig (Terminal unter Burrito)" do
      System.put_env("_IS_TTY", "1")
      on_exit(fn -> System.delete_env("_IS_TTY") end)

      {out, 2} = CLI.run(["doctor"])

      assert out =~ IO.ANSI.red()
    end
  end

  # Optimus formatiert Parse-Fehler bedingungslos farbig (IO.ANSI.red/bright/
  # reset ohne enabled?-Pruefung, siehe cli.ex format_errors/1 — Pilot-Fund
  # 2026-10-11, identisch unter Escript und Burrito-Binary). Das eigene Gate
  # haelt gepipete Ausgaben sauber, die farbige Form bleibt am Terminal.
  describe "Error-Zeilen (Optimus-Farben durch eigenes Gate)" do
    test "_IS_TTY=0: Parse-Fehler ohne ANSI, Meldungstext bleibt" do
      System.put_env("_IS_TTY", "0")
      on_exit(fn -> System.delete_env("_IS_TTY") end)

      {out, 2} = CLI.run(["definitiv-nicht-ein-befehl"])

      refute out =~ "\e["
      assert out =~ "unrecognized arguments"
    end

    test "_IS_TTY=1: Parse-Fehler farbig wie bisher" do
      System.put_env("_IS_TTY", "1")
      on_exit(fn -> System.delete_env("_IS_TTY") end)

      {out, 2} = CLI.run(["definitiv-nicht-ein-befehl"])

      assert out =~ IO.ANSI.red()
      assert out =~ IO.ANSI.bright()
    end

    test "Escript/mix-Kontext ohne Farben: Parse-Fehler ohne ANSI" do
      # Deterministisch statt umgebungsabhaengig: :ansi_enabled explizit
      # false (wie beim Pipen), _IS_TTY ungesetzt (Escript/mix-Fall).
      Application.put_env(:elixir, :ansi_enabled, false)
      on_exit(fn -> Application.delete_env(:elixir, :ansi_enabled) end)
      System.delete_env("_IS_TTY")

      {out, 2} = CLI.run(["definitiv-nicht-ein-befehl"])

      refute out =~ "\e["
      assert out =~ "unrecognized arguments"
    end
  end

  describe "Denial-Status → Exit-Code (fail-closed)" do
    test "ok und nil sind 0, jeder Fehlerstatus ist 4" do
      assert CLI.run_exit_code(nil) == 0
      assert CLI.run_exit_code(%{status: "ok"}) == 0

      for status <- ~w(capture_error write_error timeout unavailable unparseable) do
        assert CLI.run_exit_code(%{status: status}) == 4, status
      end
    end

    test "stdout bleibt pi-Ausgabe, Footer geht auf stderr und enthaelt keinen Username" do
      summary = %{
        status: "capture_error",
        denials: [],
        report_path: nil,
        error: "log fehlt"
      }

      stderr =
        capture_io(:stderr, fn ->
          assert {"scratch: /tmp/komki\npi antwort\n", 4} =
                   CLI.render_result({:run_ok, "/tmp/komki", "pi antwort", summary})
        end)

      assert stderr =~ "denials: capture FAILED (log fehlt); no report"
      refute stderr =~ System.user_home!()
    end

    test "ok-Footer nennt den relativen Berichtspfad ohne Username" do
      summary = %{
        status: "ok",
        denials: [
          %{operation: "file-read-data", target: "<scratch>/<redacted>", occurrences: 1}
        ],
        report_path: "denials/20261017T211507.000000Z-abcdef123456.json",
        error: nil
      }

      stderr =
        capture_io(:stderr, fn ->
          assert {_stdout, 0} =
                   CLI.render_result({:run_ok, "/tmp/komki", "pi antwort", summary})
        end)

      assert stderr =~ "report: denials/"
      refute stderr =~ System.user_home!()
    end
  end
end
