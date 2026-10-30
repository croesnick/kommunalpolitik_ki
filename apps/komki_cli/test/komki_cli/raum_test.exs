defmodule KomkiCli.RaumTest do
  # Ticket #268: Raum wechseln mit einem Befehl, Lockern nur ohne Session,
  # Fortsetzen nur in einem mindestens so strengen Raum.
  use ExUnit.Case, async: true

  alias KomkiCli.{Gamma, Raum, TestSupport}
  alias KomkiMediator.Templates
  alias KomkiPolicy.JSON

  setup do
    cfg = TestSupport.fixture_cfg(TestSupport.tmp_area!("komki-raum"))
    assert :written = Gamma.sync(cfg)
    assert :ok = Templates.provision!(cfg.base_dir)
    %{cfg: cfg}
  end

  defp deps(opts) do
    parent = self()

    %{
      session_running?: fn _ -> Keyword.get(opts, :session, false) end,
      run_active?: fn _ -> Keyword.get(opts, :run, false) end,
      mediator_running?: fn _ -> Keyword.get(opts, :mediator, false) end,
      restart: fn _ ->
        send(parent, :restarted)
        {:ok, :restarted}
      end
    }
  end

  defp bindings(cfg), do: room(cfg)["workspace_bindings"]

  defp room(cfg),
    do: cfg.base_dir |> Path.join("mediator/room.json") |> File.read!() |> JSON.parse() |> elem(1)

  test "anzeigen: der Default-Raum ist recherche", %{cfg: cfg} do
    assert {:raum, text} = Raum.show(cfg)
    assert text =~ "Raum        recherche"
    assert text =~ "komki raum recherche | vertraulich"
  end

  test "verschärfen geht auch mit laufender Session und startet den Vermittler neu", %{cfg: cfg} do
    assert {:ok, dir} = Raum.open_session(cfg, false)
    assert {:raum, text} = Raum.switch(cfg, "vertraulich", deps(session: true, mediator: true))
    assert text =~ "recherche → vertraulich"
    assert bindings(cfg) == Templates.vertraulich_bindings()
    assert_received :restarted
    # Die laufende Session zieht in den strengeren Raum mit.
    assert {:ok, raw} = File.read(Raum.marker_path(cfg, Path.basename(dir)))
    assert {:ok, %{"workspace_bindings" => marked}} = JSON.parse(raw)
    assert marked == Enum.sort(Templates.vertraulich_bindings())
  end

  test "lockern mit laufender Session verweigert und ändert nichts", %{cfg: cfg} do
    {:raum, _} = Raum.switch(cfg, "vertraulich", deps([]))
    before = File.read!(Path.join(cfg.base_dir, "mediator/room.json"))

    assert {:error, reason, 2} = Raum.switch(cfg, "recherche", deps(session: true))
    assert reason =~ "Session läuft noch"
    assert File.read!(Path.join(cfg.base_dir, "mediator/room.json")) == before
  end

  test "lockern während eines komki run verweigert", %{cfg: cfg} do
    {:raum, _} = Raum.switch(cfg, "vertraulich", deps([]))
    assert {:error, reason, 2} = Raum.switch(cfg, "recherche", deps(run: true))
    assert reason =~ "komki run läuft noch"
  end

  test "track_run hält den Lauf fest und räumt danach auf", %{cfg: cfg} do
    refute Raum.run_active?(cfg)
    assert :done = Raum.track_run(cfg, fn -> if Raum.run_active?(cfg), do: :done end)
    refute Raum.run_active?(cfg)
  end

  test "lockern ohne Session geht; der Rückweg ist byte-gleich die Vorlage", %{cfg: cfg} do
    {:raum, _} = Raum.switch(cfg, "vertraulich", deps([]))
    assert {:raum, text} = Raum.switch(cfg, "recherche", deps([]))
    assert text =~ "läuft nicht"
    refute_received :restarted

    assert File.read!(Path.join(cfg.base_dir, "mediator/room.json")) ==
             JSON.canonical(Templates.room())
  end

  test "unbekannter Raum und gleicher Raum", %{cfg: cfg} do
    assert {:error, reason, 2} = Raum.switch(cfg, "offen", deps([]))
    assert reason =~ "Es gibt: recherche, vertraulich"
    assert {:error, "Der Raum ist schon recherche.", 2} = Raum.switch(cfg, "recherche", deps([]))
  end

  test "eigener Raum und Raum mit Startvertrag werden nicht umgestellt", %{cfg: cfg} do
    path = Path.join(cfg.base_dir, "mediator/room.json")
    File.write!(path, JSON.canonical(Map.put(room(cfg), "workspace_bindings", ["x@1"])))
    assert {:error, reason, 2} = Raum.switch(cfg, "vertraulich", deps([]))
    assert reason =~ "Eigener Raum"

    File.write!(path, JSON.canonical(Map.put(Templates.room(), "contract", %{})))
    assert {:error, reason, 2} = Raum.switch(cfg, "vertraulich", deps([]))
    assert reason =~ "#214"
  end

  describe "Fortsetzen einer Session" do
    # Jede Session hat ein eigenes Verzeichnis (Ticket #295); pi legt die
    # Session-Datei darin erst mit der ersten Nachricht an.
    defp talk!(dir), do: File.write!(Path.join(dir, "verlauf.jsonl"), "{}\n")

    defp open!(cfg, continue?) do
      assert {:ok, dir} = Raum.open_session(cfg, continue?)
      dir
    end

    test "jede neue Session bekommt ein eigenes Verzeichnis", %{cfg: cfg} do
      a = open!(cfg, false)
      talk!(a)
      b = open!(cfg, false)

      assert a != b
      assert Path.dirname(a) == KomkiCli.Pi.sessions_root(cfg)
      assert Raum.session_dir(cfg) == b
    end

    test "ohne frühere Unterhaltung nein, auch nicht mit Dateien von vor #295", %{cfg: cfg} do
      root = KomkiCli.Pi.sessions_root(cfg)
      File.mkdir_p!(root)
      File.write!(Path.join(root, "alt.jsonl"), "{}\n")
      _leer = open!(cfg, false)

      assert {:error, reason, 2} = Raum.open_session(cfg, true)
      assert reason =~ "keine frühere Session"
    end

    test "ohne Markierung nein", %{cfg: cfg} do
      dir = Path.join(KomkiCli.Pi.sessions_root(cfg), "2026-10-30T12-00-00-000000Z")
      File.mkdir_p!(dir)
      talk!(dir)

      assert {:error, reason, 2} = Raum.open_session(cfg, true)
      assert reason =~ "ohne --continue"
    end

    test "im gleichen oder strengeren Raum ja, im lockereren nein", %{cfg: cfg} do
      dir = open!(cfg, false)
      talk!(dir)
      assert open!(cfg, true) == dir

      {:raum, _} = Raum.switch(cfg, "vertraulich", deps([]))
      assert open!(cfg, true) == dir

      {:raum, _} = Raum.switch(cfg, "recherche", deps([]))
      assert {:error, reason, 2} = Raum.open_session(cfg, true)
      assert reason =~ "lief im Raum vertraulich"
      assert reason =~ "komki raum vertraulich"
    end

    test "neue Session ohne Unterhaltung: die vorige bleibt mit ihrem Raum", %{cfg: cfg} do
      {:raum, _} = Raum.switch(cfg, "vertraulich", deps([]))
      vertraulich = open!(cfg, false)
      talk!(vertraulich)

      {:raum, _} = Raum.switch(cfg, "recherche", deps([]))
      # Neue Session in recherche, sofort /quit: pi schreibt keine Datei.
      leer = open!(cfg, false)

      assert {:error, reason, 2} = Raum.open_session(cfg, true)
      assert reason =~ "lief im Raum vertraulich"
      refute File.exists?(leer)

      {:raum, _} = Raum.switch(cfg, "vertraulich", deps([]))
      assert open!(cfg, true) == vertraulich
    end

    test "verschärfen mit laufender Session zieht ihre Markierung mit", %{cfg: cfg} do
      dir = open!(cfg, false)
      talk!(dir)
      {:raum, _} = Raum.switch(cfg, "vertraulich", deps(session: true))
      {:raum, _} = Raum.switch(cfg, "recherche", deps([]))

      assert {:error, reason, 2} = Raum.open_session(cfg, true)
      assert reason =~ "lief im Raum vertraulich"
    end
  end

  test "strenger heißt: enthält alle Bindungen" do
    assert Raum.at_least_as_strict?(
             Templates.vertraulich_bindings(),
             Templates.recherche_bindings()
           )

    refute Raum.at_least_as_strict?(
             Templates.recherche_bindings(),
             Templates.vertraulich_bindings()
           )
  end
end
