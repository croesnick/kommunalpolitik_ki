defmodule KomkiCli.DoctorBootTest do
  @moduledoc """
  Integration: das generierte Profil bootet (`sandbox-exec` + `/usr/bin/true`
  + `/bin/sh -c 'exit 0'` unter dem Profil). Die Tests laufen nur, wenn
  (`a`) sandbox-exec vorhanden ist — GitHub-Actions-Linux-Runner haben kein
  `/usr/bin/sandbox-exec` und zählen dann null Tests — und (`b`) das
  verifizierte GGUF-Artefakt der Sandbox-Forschung am erwarteten Pfad
  liegt; ohne beides findet dieser Modul keine Tests statt.
  """

  use ExUnit.Case, async: false

  alias KomkiCli.Config

  @sandbox_exec System.find_executable("sandbox-exec")

  if @sandbox_exec != nil and Config.default_probe_gguf() != nil do
    # Aliase innerhalb der Bedingung: Im Ruhezustand (kein sandbox-exec wie
    # auf CI-Linux, oder kein Staging-GGUF) kompiliert der Block nicht und
    # warnt nicht ueber unbenutzte Aliase.
    alias KomkiCli.{CLI, TestSupport}

    # Eine Instanz fuer alle Tests dieses Moduls (setup_all): init ist der
    # 17-GB-Kopiervorgang aus dem Staging — pro Test wiederholt waere das
    # reine Wartezeit. Eigener Port: Der run-Fail-Fast-Fall muss
    # deterministisch "nicht aktiv" sehen, egal ob auf dem Host gerade ein
    # echter llama-server laeuft.
    #
    # Vermittler-Staging (Ticket #102): init entdeckt komki-mediator ueber
    # PATH oder <base>/bin — da das echte Escript des Parallel-Lane hier
    # nicht existiert, liegt fuer die presence-only-Doctor-Klasse eine
    # Platzhalter-Datei im Instanz-bin (doctor prueft Praesenz, nicht Leben;
    # bei echten Launches verantwortet `up` die Binary).
    setup_all do
      home = TestSupport.tmp_area!("komki-boot")
      System.put_env("KOMKI_HOME", home)

      on_exit(fn -> System.delete_env("KOMKI_HOME") end)

      fake_mediator = Path.join([home, "bin", "komki-mediator"])
      File.mkdir_p!(Path.dirname(fake_mediator))
      File.write!(fake_mediator, "komki-mediator-platzhalter ( teste-Instanz )")

      # Ticket #146: Egress und Connectoren ebenso als Platzhalter (Praesenz
      # und Profil-Identitaet; gestartet werden sie hier nicht).
      for name <- [
            "komki-egress",
            "komki-connector-ris",
            "komki-connector-web",
            "komki-connector-vault",
            "komki-connector-documents"
          ] do
        File.write!(Path.join([home, "bin", name]), name <> "-platzhalter")
      end

      {init_out, 0} = CLI.run(["init", "--port", "59999"])
      {:ok, init_out: init_out}
    end

    test "init ok, gepinntes SHA verifiziert", %{init_out: init_out} do
      assert init_out =~ "init ok"
      assert init_out =~ "gguf-sha256:  " <> Config.expected_gguf_sha256()
    end

    test "doctor: alle Checks grün inklusive Boot-Gate" do
      # cfg aus der Instanz der setup_all-Phase: der llama-Boot-Probe-Check
      # heisst "boot " <> llama-server-Pfad (steps.ex: boot_l) — genau
      # gepinnt statt Substring ("llama-server" matcht auch den Tools-Check,
      # "boot " ist durch die pi-Probes subsumiert).
      cfg = Config.load!(Config.config_path(Config.default_base()))

      {out_doctor, 0} = CLI.run(["doctor"])
      assert out_doctor =~ "doctor: ok"
      assert out_doctor =~ "boot /usr/bin/true"
      assert out_doctor =~ "boot /bin/sh"
      assert out_doctor =~ "llama profile"
      # bestehende pi-Probes + der neue llama-server-Boot-Probe unter seinem Profil
      assert out_doctor =~ "boot " <> cfg.llama_server_bin
      refute out_doctor =~ "FAIL"
    end

    # Ticket #176: run startet fehlende Prozesse selbst (wie up). In diesem
    # Testumfeld scheitert der Start; die Ursache kommt mit Runtime-Exit 4,
    # statt dass run auf 'komki up' verweist.
    #
    # Der Test bootet den echten llama-server mit dem 17-GB-Modell (am
    # eigenen Port) und scheitert danach am Egress-Platzhalter: allein der
    # Modell-Boot dauert auf diesem Host rund 45 s, das ExUnit-Default-
    # Limit von 60 s kippt deshalb unter paralleler Last (Abschluss-Sweep
    # zu #290: 2 von 3 Laeufe rot, mit --trace durchlaufen).
    @tag timeout: 180_000
    test "run ohne laufenden llama-server startet selbst; scheitert der Start, kommt die Ursache (Exit 4)" do
      # Der Startversuch kann einen echten llama-server hochfahren: danach
      # immer stoppen, sonst bleibt er als Waise auf dem Testport.
      on_exit(fn -> CLI.run(["down"]) end)

      {out_run, 4} = CLI.run(["run", "hallo"])
      refute out_run =~ "'komki up' zuerst"
      assert out_run =~ "egress"
    end

    test "down ohne Boot-Gate: bereits gestoppt ist Erfolg (Exit 0)" do
      {out_down, 0} = CLI.run(["down"])
      assert out_down =~ "bereits gestoppt (kein pidfile)"
    end

    test "down raeumt stale pidfile auf, ohne zu toeten (Exit 0)" do
      home = System.get_env("KOMKI_HOME")
      pidfile = Path.join([home, "tmp", "llama-server.pid"])
      File.mkdir_p!(Path.dirname(pidfile))

      # Pid 99998 (macOS' hoechste normale Pid) existiert im Testumfeld nicht:
      # Identitaetscheck verweigert das Toeten, aber der Aufraeumweg entfernt
      # das stale pidfile.
      File.write!(pidfile, "99998\n")

      {out_down, 0} = CLI.run(["down"])
      assert out_down =~ "ist nicht (mehr) llama-server"
      assert out_down =~ "pidfile entfernt"
      refute File.exists?(pidfile)
    end
  end
end
