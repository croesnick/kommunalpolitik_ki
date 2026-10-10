defmodule KomkiCli.CLITest do
  # KOMKI_HOME ist eine globale Umgebung; keine parallelen Module (Race).
  use ExUnit.Case, async: false

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

    test "session-chain ohne config verweigert (Exit 2)" do
      {out, 2} = CLI.run(["session-chain"])
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
end
