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
    setup_all do
      home = TestSupport.tmp_area!("komki-boot")
      System.put_env("KOMKI_HOME", home)

      on_exit(fn -> System.delete_env("KOMKI_HOME") end)

      {init_out, 0} = CLI.run(["init", "--port", "59999"])
      {:ok, init_out: init_out}
    end

    test "init ok, gepinntes SHA verifiziert", %{init_out: init_out} do
      assert init_out =~ "init ok"
      assert init_out =~ "gguf-sha256:  " <> Config.expected_gguf_sha256()
    end

    test "doctor: alle Checks gruen inklusive Boot-Gate" do
      {out_doctor, 0} = CLI.run(["doctor"])
      assert out_doctor =~ "doctor: ok"
      assert out_doctor =~ "boot /usr/bin/true"
      assert out_doctor =~ "boot /bin/sh"
      refute out_doctor =~ "FAIL"
    end

    test "run ohne laufenden llama-server: fail-fast mit Hinweis (Exit 2)" do
      {out_run, 2} = CLI.run(["run", "hallo"])
      assert out_run =~ "llama-server nicht aktiv"
      assert out_run =~ "'komki up' zuerst"
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
