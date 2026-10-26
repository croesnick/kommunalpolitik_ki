defmodule KomkiCli.SessionIntakeTest do
  @moduledoc """
  Hermetische Aufnahme-Tests (Ticket #92): kein llama, kein tmux, kein
  Vermittler-Boot. Die Engine laeuft echt gegen die importierte
  Label-Registry; nur Prozess-Liveness bleibt aussen vor.
  """

  use ExUnit.Case, async: true

  alias KomkiCli.{Config, LabelStore, SessionIntake, StartContract, TestSupport}
  alias KomkiCli.LabelStore.ObjectRef

  @seed_path Path.join([:code.priv_dir(:komki_cli), "fixtures", "registry-seed.json"])

  setup do
    base = Config.canonical(TestSupport.tmp_area!("komki-session-intake"))
    db = Path.join(base, "registry.db")
    {:ok, _counts} = LabelStore.import_registry(db, seed_term())

    {:ok, base: base, db: db}
  end

  # ========================================================================
  # permit
  # ========================================================================

  test "permit: Datei an content_ref, classify ratsarbeit@1 -> checked_label ist B_W", %{
    base: base,
    db: db
  } do
    file = write_source!(base, "brief-4711.txt", "Ratsunterlage")
    register_classified!(db, "brief-4711", file, ["ratsarbeit@1"])

    contract =
      contract_json(["ratsarbeit@1"], ["brief-4711@v1"], purpose: "sitzungsvorbereitung")

    room = load_room!(base, contract)

    assert {:ok, intake} = plan(db, base, room, [file])

    [entry] = intake.entries
    assert entry.status == "permit"
    assert entry.checked_label == ["ratsarbeit@1"]
    assert entry.labels == ["ratsarbeit@1"]

    staged = Path.join([base, "mediator", "documents", "brief-4711.md"])
    refute File.exists?(staged)
    stage!(intake)
    assert File.read!(staged) == "Ratsunterlage"

    # Raumdokument (#92 nach #169): Objekt mit Typ, Version und λ(x) in
    # room.json, damit admit_document es aufloest (#134).
    {:ok, room_json} = KomkiPolicy.JSON.parse(File.read!(room.path))

    assert room_json["objects"]["brief-4711"] == %{
             "type" => "document",
             "version" => "v1",
             "labels" => ["ratsarbeit@1"]
           }
  end

  test "kein UTF-8-Text -> Fehler, nichts abgelegt", %{base: base, db: db} do
    file = write_source!(base, "scan.txt", <<0xFF, 0xFE, 0x00, 0x41>>)
    register_classified!(db, "scan", file, ["ratsarbeit@1"])
    contract = contract_json(["ratsarbeit@1"], ["scan@v1"], purpose: "sitzungsvorbereitung")
    room = load_room!(base, contract)

    assert {:error, reason} = plan(db, base, room, [file])
    assert reason =~ "kein UTF-8-Text"
    refute File.exists?(Path.join([base, "mediator", "documents", "scan.md"]))
  end

  # ========================================================================
  # D.1-Regression: oeffentliche Datei gegen ALLE Raumbindungen pruefen
  # ========================================================================

  test "D.1: oeffentliche Datei gegen zweite Bindung -> deny binding_condition_false", %{
    base: base,
    db: db
  } do
    file = write_source!(base, "offen.txt", "Oeffentliche Notiz")
    register_classified!(db, "offen", file, ["lizenz-namensnennung@1"])

    bindings = ["lizenz-namensnennung@1", "ratsarbeit@1"]
    contract = contract_json(bindings, ["offen@v1"], purpose: "offene-recherche")
    room = load_room!(base, contract)

    assert {:refused, [entry]} = plan(db, base, room, [file])
    assert entry.status == "deny"

    assert Enum.any?(
             entry.blockers,
             &(&1["code"] == "binding_condition_false" and &1["binding"] == "ratsarbeit@1")
           )

    assert entry.checked_label == bindings
    refute File.exists?(Path.join([base, "mediator", "documents", "offen.md"]))
  end

  test "D.1-Gegenprobe: nur lizenz-namensnennung@1 als B_W -> permit", %{base: base, db: db} do
    file = write_source!(base, "offen.txt", "Oeffentliche Notiz")
    register_classified!(db, "offen", file, ["lizenz-namensnennung@1"])

    contract =
      contract_json(["lizenz-namensnennung@1"], ["offen@v1"], purpose: "offene-recherche")

    room = load_room!(base, contract)

    assert {:ok, intake} = plan(db, base, room, [file])
    [entry] = intake.entries
    assert entry.status == "permit"
    assert entry.checked_label == ["lizenz-namensnennung@1"]
    refute File.exists?(Path.join([base, "mediator", "documents", "offen.md"]))
    stage!(intake)
    assert File.exists?(Path.join([base, "mediator", "documents", "offen.md"]))
  end

  # ========================================================================
  # Quarantaene
  # ========================================================================

  test "unregistrierte Datei: Quarantaene im Store, deny object_quarantine, nichts in arbeit", %{
    base: base,
    db: db
  } do
    file = write_source!(base, "neue-notiz.txt", "Noch nicht klassifiziert")
    contract = contract_json(["ratsarbeit@1"], [], purpose: "sitzungsvorbereitung")
    room = load_room!(base, contract)

    assert {:refused, [entry]} = plan(db, base, room, [file])
    assert entry.quarantine_created == true
    assert entry.status == "deny"
    assert Enum.any?(entry.blockers, &(&1["code"] == "object_quarantine"))
    assert entry.equivalent_cli =~ "komki label quarantine neue-notiz@v1"

    {:ok, _bindings, objects} = LabelStore.list(db)
    quarantined = Enum.find(objects, &(&1.object == "neue-notiz@v1"))
    assert quarantined.classification == "quarantine"
    assert quarantined.labels == []

    # Zweiter Plan trifft den letzten Store-Zustand, ohne erneut zu
    # quarantainen, und bleibt eine Verweigerung.
    assert {:refused, [second]} = plan(db, base, room, [file])
    assert second.quarantine_created == false
    assert second.status == "deny"
    assert Enum.any?(second.blockers, &(&1["code"] == "object_quarantine"))

    refute File.exists?(Path.join([base, "mediator", "documents", "neue-notiz.md"]))
  end

  test "Quelle unter den Raumdokumenten wird abgewiesen, nichts geaendert", %{
    base: base,
    db: db
  } do
    File.mkdir_p!(Path.join([base, "mediator", "documents"]))
    file = Path.join([base, "mediator", "documents", "schon-da.md"])
    File.write!(file, "Quarantaene am Arbeitsort")

    contract = contract_json(["ratsarbeit@1"], [], purpose: "sitzungsvorbereitung")
    room = load_room!(base, contract)

    assert {:error, reason} = plan(db, base, room, [file])
    assert reason =~ "Vermittler-Verzeichnis"
    assert File.read!(file) == "Quarantaene am Arbeitsort"
  end

  # ========================================================================
  # Fehlender Fakt und falscher Raum
  # ========================================================================

  test "fehlender Fakt purpose wird fuer die Dateiaufnahme fail-closed verweigert", %{
    base: base,
    db: db
  } do
    file = write_source!(base, "brief.txt", "Ratsunterlage")
    register_classified!(db, "brief", file, ["ratsarbeit@1"])

    contract = contract_json(["ratsarbeit@1"], ["brief@v1"], purpose: nil)
    room = load_room!(base, contract)

    assert {:error, reason} = plan(db, base, room, [file])
    assert reason =~ "facts.purpose"
    refute File.exists?(Path.join([base, "mediator", "documents", "brief.md"]))
  end

  test "falscher Raum: ratsarbeit@1 gegen B_W lizenz -> deny label_not_included", %{
    base: base,
    db: db
  } do
    file = write_source!(base, "brief.txt", "Ratsunterlage")
    register_classified!(db, "brief", file, ["ratsarbeit@1"])

    contract =
      contract_json(["lizenz-namensnennung@1"], ["brief@v1"], purpose: "sitzungsvorbereitung")

    room = load_room!(base, contract)

    assert {:refused, [entry]} = plan(db, base, room, [file])
    assert entry.status == "deny"
    assert Enum.any?(entry.blockers, &(&1["code"] == "label_not_included"))

    assert Enum.any?(entry.remedies, fn remedy ->
             Enum.any?(remedy["transitions"], fn transition ->
               transition["type"] == "neuer_raum" and
                 transition["required_bindings"] == ["ratsarbeit@1"]
             end)
           end)
  end

  # ========================================================================
  # B1: Pfad-content_ref bindet keine Bytes
  # ========================================================================

  test "B1: ausgetauschte Bytes bei Pfad-content_ref -> Fehler, nie permit", %{
    base: base,
    db: db
  } do
    file = write_source!(base, "brief.txt", "Original")
    register_with_path_ref!(db, "brief", file, ["ratsarbeit@1"])

    # Bytes am registrierten Pfad austauschen.
    File.write!(file, "Manipuliert")

    contract = contract_json(["ratsarbeit@1"], ["brief@v1"], purpose: "sitzungsvorbereitung")
    room = load_room!(base, contract)

    assert {:error, reason} = plan(db, base, room, [file])
    assert reason =~ "Pfad-content_ref"
    assert reason =~ "sha256"
    refute File.exists?(Path.join([base, "mediator", "documents", "brief.md"]))
  end

  # ========================================================================
  # S6a: Eingangsrechte ueberschreiben den Raumfakt
  # ========================================================================

  test "Objekt mit Labels, aber nicht in eingangsrechte -> deny basis_right_false", %{
    base: base,
    db: db
  } do
    file = write_source!(base, "brief.txt", "Ratsunterlage")
    register_classified!(db, "brief", file, ["ratsarbeit@1"])

    # Raumfakt has_object_access_right ist absichtlich true (Helper); der
    # Intake muss ihn aus den leeren eingangsrechten auf false setzen.
    contract = contract_json(["ratsarbeit@1"], [], purpose: "sitzungsvorbereitung")
    room = load_room!(base, contract)

    assert {:refused, [entry]} = plan(db, base, room, [file])
    assert entry.status == "deny"

    assert Enum.any?(
             entry.blockers,
             &(&1["code"] == "basis_right_false" and
                 &1["condition"] == "has_object_access_right")
           )

    refute File.exists?(Path.join([base, "mediator", "documents", "brief.md"]))
  end

  # ========================================================================
  # S6b: gemischter Batch
  # ========================================================================

  test "gemischter Batch permit+deny -> refused, keine Datei in arbeit", %{base: base, db: db} do
    permit = write_source!(base, "permit.txt", "Erlaubt")
    deny = write_source!(base, "abgelehnt.txt", "Nicht registriert")
    register_classified!(db, "permit", permit, ["ratsarbeit@1"])

    contract = contract_json(["ratsarbeit@1"], ["permit@v1"], purpose: "sitzungsvorbereitung")
    room = load_room!(base, contract)

    assert {:refused, entries} = plan(db, base, room, [permit, deny])
    assert Enum.sort(Enum.map(entries, & &1.status)) == ["deny", "permit"]

    refute File.exists?(Path.join([base, "mediator", "documents", "permit.md"]))
    refute File.exists?(Path.join([base, "mediator", "documents", "abgelehnt.md"]))
  end

  # ========================================================================
  # S6c: Vertragsnegativfaelle
  # ========================================================================

  test "Vertrag: unsortierte und doppelte Bindings werden abgewiesen", %{base: base, db: db} do
    compiled = compiled!(db)

    unsorted =
      Map.put(
        contract_json(["ratsarbeit@1"], [], purpose: "x"),
        "bindings",
        ["ratsarbeit@1", "lizenz-namensnennung@1"]
      )

    path = write_room!(base, unsorted)
    assert {:error, reason} = StartContract.load(path, compiled)
    assert reason =~ "sortiert"

    duplicate =
      Map.put(
        contract_json(["ratsarbeit@1"], [], purpose: "x"),
        "bindings",
        ["ratsarbeit@1", "ratsarbeit@1"]
      )

    path = write_room!(base, duplicate)
    assert {:error, reason} = StartContract.load(path, compiled)
    assert reason =~ "sortiert"
  end

  test "Vertrag: unbekannte Bindung, ungueltiges OBJ@VER, doppelte Eingangsrechte", %{
    base: base,
    db: db
  } do
    compiled = compiled!(db)

    unknown = contract_json(["gibt-es-nicht@1"], [], purpose: "x")
    assert {:error, reason} = StartContract.load(write_room!(base, unknown), compiled)
    assert reason =~ "unbekannte Bindung"

    invalid_ref = contract_json(["ratsarbeit@1"], ["brief"], purpose: "x")
    assert {:error, reason} = StartContract.load(write_room!(base, invalid_ref), compiled)
    assert reason =~ "OBJ@VER"

    duplicate = contract_json(["ratsarbeit@1"], ["brief@v1", "brief@v1"], purpose: "x")
    assert {:error, reason} = StartContract.load(write_room!(base, duplicate), compiled)
    assert reason =~ "Duplikate"
  end

  test "Vertrag: unbekannte verantwortliche Person und leeres B_W", %{base: base, db: db} do
    compiled = compiled!(db)

    unknown_person =
      Map.put(
        contract_json(["ratsarbeit@1"], [], purpose: "x"),
        "verantwortliche_person",
        "niemand"
      )

    assert {:error, reason} = StartContract.load(write_room!(base, unknown_person), compiled)
    assert reason =~ "kein Beobachter"

    empty = contract_json([], [], purpose: "x")
    assert {:ok, contract} = StartContract.load(write_room!(base, empty), compiled)
    assert {:error, reason} = StartContract.validate_for_intake(contract)
    assert reason =~ "bindings ist leer"
  end

  test "Vertrag: fehlende/unbekannte Felder, kaputtes JSON, fehlende room.json", %{
    base: base,
    db: db
  } do
    compiled = compiled!(db)
    contract = contract_json(["ratsarbeit@1"], ["brief@v1"], purpose: "x")

    missing = Map.delete(contract, "auftrag")
    assert {:error, reason} = StartContract.load(write_room!(base, missing), compiled)
    assert reason =~ "fehlen"

    unknown = Map.put(contract, "foo", "bar")
    assert {:error, reason} = StartContract.load(write_room!(base, unknown), compiled)
    assert reason =~ "unbekannte contract-Felder"

    broken = Path.join([base, "mediator", "brochen.json"])
    File.write!(broken, "{")
    assert {:error, reason} = StartContract.load(broken, compiled)
    assert reason =~ "ungueltiges JSON"

    assert {:error, reason} = StartContract.load(Path.join(base, "fehlt.json"), compiled)
    assert reason =~ "nicht lesbar"
  end

  # ========================================================================
  # S6d: Pfad-Sperren
  # ========================================================================

  test "Pfad-Sperren: mediator, runs, DB-Artefakte, Symlink, Verzeichnis", %{
    base: base,
    db: db
  } do
    context = %{base_dir: base, pi_home: Path.join(base, "pi-home"), db: db}

    mediator_file = Path.join([base, "mediator", "quelle.txt"])
    File.mkdir_p!(Path.dirname(mediator_file))
    File.write!(mediator_file, "x")
    assert {:error, reason} = SessionIntake.validate_paths([mediator_file], context)
    assert reason =~ "Vermittler"

    runs_file = Path.join([base, "runs", "quelle.txt"])
    File.mkdir_p!(Path.dirname(runs_file))
    File.write!(runs_file, "x")
    assert {:error, reason} = SessionIntake.validate_paths([runs_file], context)
    assert reason =~ "runs"

    assert {:error, reason} = SessionIntake.validate_paths([db], context)
    assert reason =~ "Registry-DB"

    wal = db <> "-wal"
    File.write!(wal, "x")
    assert {:error, reason} = SessionIntake.validate_paths([wal], context)
    assert reason =~ "Begleitdatei"

    pi_home = Path.join(base, "pi-home")
    File.mkdir_p!(pi_home)
    target = Path.join(pi_home, "geheim.txt")
    File.write!(target, "x")
    link = Path.join([base, "quellen", "link.txt"])
    File.mkdir_p!(Path.dirname(link))
    File.ln_s!(target, link)
    assert {:error, reason} = SessionIntake.validate_paths([link], context)
    assert reason =~ "pi-home"

    assert {:error, reason} = SessionIntake.validate_paths([base], context)
    assert reason =~ "Verzeichnis"

    dotdot = Path.join([base, "quellen", "..", "runs", "quelle.txt"])
    assert {:error, reason} = SessionIntake.validate_paths([dotdot], context)
    assert reason =~ "runs"
  end

  test "relative Pfade werden kanonisiert; externe DB sperrt nur DB-Artefakte", %{
    base: base,
    db: db
  } do
    context = %{base_dir: base, pi_home: Path.join(base, "pi-home"), db: db}
    file = write_source!(base, "relativ.txt", "x")
    relative = Path.relative_to(file, File.cwd!())
    assert {:ok, [canonical]} = SessionIntake.validate_paths([relative], context)
    assert canonical == Config.canonical(file)

    ext = Path.join(base, "external-store")
    File.mkdir_p!(ext)
    ext_db = Path.join(ext, "registry.db")
    File.write!(ext_db, "")

    source = Path.join(ext, "quelle.txt")
    File.write!(source, "x")

    external_context = %{context | db: ext_db}

    # Neben der externen DB ist erlaubt; die DB-Datei selbst nicht.
    assert {:ok, [_]} = SessionIntake.validate_paths([source], external_context)
    assert {:error, _} = SessionIntake.validate_paths([ext_db], external_context)
  end

  # ========================================================================
  # S6e: CLI/Steps-Naht, Reihenfolge, Exit-Klassen
  # ========================================================================

  test "CLI-Parser erhaelt die Dateireihenfolge und versteht --" do
    assert {:ok, ["a", "b", "c"], _opts} = KomkiCli.CLI.parse_session_argv(["a", "b", "c"])
    assert {:ok, ["a", "b", "c"], _opts} = KomkiCli.CLI.parse_session_argv(["a", "--", "b", "c"])
  end

  test "CLI-Parser lehnt Optionswerte ab, die wie ein Flag aussehen" do
    assert {:error, reason} = KomkiCli.CLI.parse_session_argv(["--db", "--room"])
    assert reason =~ "kein Flag"
  end

  test "CLI rendert eine Verweigerung mit Exit 3" do
    assert {out, 3} = KomkiCli.CLI.render_session_refused(["datei: x -> y deny"])
    assert out =~ "session verweigert"
  end

  test "Steps.session_plan: --continue mit Dateien -> Exit 2", %{base: base, db: db} do
    file = write_source!(base, "brief.txt", "x")
    register_classified!(db, "brief", file, ["ratsarbeit@1"])
    write_contract_room!(base, ["ratsarbeit@1"], ["brief@v1"])

    assert {:error, reason, 2} =
             KomkiCli.Steps.session_plan(session_plan_opts(base, [file], %{"continue" => "true"}))

    assert reason =~ "neuem Start"
  end

  test "Steps.session_plan: laufende tmux-Session mit Dateien -> Exit 2", %{base: base, db: db} do
    file = write_source!(base, "brief.txt", "x")
    register_classified!(db, "brief", file, ["ratsarbeit@1"])
    write_contract_room!(base, ["ratsarbeit@1"], ["brief@v1"])

    assert {:error, reason, 2} =
             KomkiCli.Steps.session_plan(
               session_plan_opts(base, [file], %{tmux_running?: fn -> true end})
             )

    assert reason =~ "läuft bereits"
  end

  test "Steps.session_plan: permit end-to-end ueber die CLI-Naht", %{base: base, db: db} do
    file = write_source!(base, "brief.txt", "Ratsunterlage")
    register_classified!(db, "brief", file, ["ratsarbeit@1"])
    write_contract_room!(base, ["ratsarbeit@1"], ["brief@v1"])

    assert {:session_plan, header, intake} =
             KomkiCli.Steps.session_plan(session_plan_opts(base, [file]))

    assert Enum.join(header, "\n") =~ "B_W: ratsarbeit@1"
    assert [%{status: "permit"}] = intake.entries
    refute File.exists?(Path.join([base, "mediator", "documents", "brief.md"]))
  end

  test "Steps.session_plan: fehlende Datei -> Exit 2", %{base: base} do
    missing = Path.join(base, "fehlt.txt")

    assert {:error, reason, 2} =
             KomkiCli.Steps.session_plan(session_plan_opts(base, [missing]))

    assert reason =~ "nicht gefunden" or reason =~ "nicht statbar"
  end

  test "Steps.session_plan: Verweigerung ist ein Refusal-Tupel (CLI Exit 3)", %{
    base: base,
    db: db
  } do
    file = write_source!(base, "brief.txt", "x")
    register_classified!(db, "brief", file, ["ratsarbeit@1"])
    write_contract_room!(base, ["lizenz-namensnennung@1"], ["brief@v1"])

    assert {:session_refused, header, [entry]} =
             KomkiCli.Steps.session_plan(session_plan_opts(base, [file]))

    assert entry.status == "deny"

    assert Enum.join(header, "\n") =~ "label_not_included" or entry.blockers != []
  end

  # ========================================================================
  # S2: Staging erst nach Liveness
  # ========================================================================

  test "permit-Datei + toter llama/Mediator -> keine Datei in arbeit", %{base: base, db: db} do
    file = write_source!(base, "brief.txt", "Ratsunterlage")
    register_classified!(db, "brief", file, ["ratsarbeit@1"])
    contract = contract_json(["ratsarbeit@1"], ["brief@v1"], purpose: "sitzungsvorbereitung")
    room = load_room!(base, contract)

    assert {:ok, intake} = plan(db, base, room, [file])
    refute File.exists?(Path.join([base, "mediator", "documents", "brief.md"]))

    cfg = TestSupport.fixture_cfg(base)
    cfg = %{cfg | port: 59_999}

    assert {:error, _reason, 2} =
             KomkiCli.Steps.session_start(intake, %{
               tmux_running?: fn -> false end,
               config: cfg
             })

    refute File.exists?(Path.join([base, "mediator", "documents", "brief.md"]))
  end

  test "Kollision im Batch wird vor dem ersten Kopieren erkannt", %{base: base, db: db} do
    first = write_source!(base, "a.txt", "A")
    second = write_source!(base, "b.txt", "B")
    register_classified!(db, "a", first, ["ratsarbeit@1"])
    register_classified!(db, "b", second, ["ratsarbeit@1"])

    File.mkdir_p!(Path.join([base, "mediator", "documents"]))
    File.write!(Path.join([base, "mediator", "documents", "b.md"]), "fremd")

    contract = contract_json(["ratsarbeit@1"], ["a@v1", "b@v1"], purpose: "sitzungsvorbereitung")
    room = load_room!(base, contract)

    assert {:error, reason} = plan(db, base, room, [first, second])
    assert reason =~ "anderen Bytes"
    refute File.exists?(Path.join([base, "mediator", "documents", "a.md"]))
  end

  # ========================================================================
  # Header mit/ohne Vertrag
  # ========================================================================

  test "Header mit Vertrag nennt B_W, auftrag, zweck+quelle, eingangsrechte, Vertrag-Hash", %{
    base: base
  } do
    contract = contract_json(["ratsarbeit@1"], ["brief@v1"], purpose: "sitzungsvorbereitung")
    room = load_room!(base, contract)
    header = room |> StartContract.header() |> Enum.join("\n")

    assert header =~ "Startvertrag (sha256:"
    assert header =~ "room: "
    assert header =~ "registry: komki-synth-demo"
    assert header =~ "B_W: ratsarbeit@1"
    assert header =~ "auftrag: Sitzungsvorbereitung"
    assert header =~ "sitzungsvorbereitung"
    assert header =~ "quelle: auftrags-verwaltung"
    assert header =~ "eingangsrechte: brief@v1"
  end

  test "Header ohne Vertrag: Hinweis, Dateiaufnahme braucht die vier Felder", %{base: base} do
    room = write_room!(base, nil)
    {:ok, contract} = StartContract.load(room, nil)
    header = contract |> StartContract.header() |> Enum.join("\n")

    assert header =~ "kein Startvertrag"
    assert header =~ "bindings"
    assert header =~ "auftrag"
    assert header =~ "verantwortliche_person"
    assert header =~ "eingangsrechte"
  end

  # ========================================================================
  # Randfaelle
  # ========================================================================

  test "fehlende Datei wird vor jeder Aufnahme abgewiesen", %{base: base, db: db} do
    context = %{base_dir: base, pi_home: Path.join(base, "pi-home"), db: db}
    missing = Path.join(base, "gibts-nicht.txt")

    assert {:error, reason} = SessionIntake.validate_paths([missing], context)
    assert reason =~ "nicht gefunden" or reason =~ "nicht statbar"
  end

  test "Duplikat in argv wird nach Kanonisierung dedupliziert", %{base: base, db: db} do
    file = write_source!(base, "brief.txt", "Inhalt")
    context = %{base_dir: base, pi_home: Path.join(base, "pi-home"), db: db}

    assert {:ok, [deduped]} = SessionIntake.validate_paths([file, file], context)
    assert deduped == Config.canonical(file)
  end

  test "Nicht-Liste statt Dateiliste ist ein Fehler, kein stilles Leerlaufen", %{
    base: base,
    db: db
  } do
    context = %{base_dir: base, pi_home: Path.join(base, "pi-home"), db: db}

    assert {:error, reason} = SessionIntake.validate_paths(nil, context)
    assert reason =~ "Dateiliste"
  end

  test "SessionIntake.plan validiert Pfade selbst (nicht nur Steps)", %{base: base, db: db} do
    file = write_source!(base, "brief.txt", "x")
    register_classified!(db, "brief", file, ["ratsarbeit@1"])
    contract = contract_json(["ratsarbeit@1"], ["brief@v1"], purpose: "sitzungsvorbereitung")
    room = load_room!(base, contract)

    assert {:error, reason} = plan(db, base, room, [Path.join(base, "fehlt.txt")])
    assert reason =~ "nicht gefunden" or reason =~ "nicht statbar"
  end

  test "Kollision mit vorhandenem Raumdokument (andere Bytes) -> Exit-2-Fehler", %{
    base: base,
    db: db
  } do
    file = write_source!(base, "brief.txt", "neue Bytes")
    register_classified!(db, "brief", file, ["ratsarbeit@1"])

    File.mkdir_p!(Path.join([base, "mediator", "documents"]))
    File.write!(Path.join([base, "mediator", "documents", "brief.md"]), "alte Bytes")

    contract = contract_json(["ratsarbeit@1"], ["brief@v1"], purpose: "sitzungsvorbereitung")
    room = load_room!(base, contract)

    assert {:error, reason} = plan(db, base, room, [file])
    assert reason =~ "anderen Bytes"
  end

  test "Quelle im pi-home ist ein Agenten-Schreibscope", %{base: base, db: db} do
    pi_home = Path.join(base, "pi-home")
    File.mkdir_p!(pi_home)
    file = Path.join(pi_home, "brief.txt")
    File.write!(file, "Im Agentenbereich")

    context = %{base_dir: base, pi_home: pi_home, db: db}

    assert {:error, reason} = SessionIntake.validate_paths([file], context)
    assert reason =~ "pi-home"
  end

  test "leere Registry liefert den Import-Hinweis", %{base: base} do
    db = Path.join(base, "leer.db")

    assert {:error, reason} = SessionIntake.load_registry(db)
    assert reason =~ "Registry leer"
    assert reason =~ "komki label import"
  end

  test "--continue mit Dateien ist ein Usage-Fehler (#98)", %{base: base} do
    file = write_source!(base, "brief.txt", "Inhalt")

    assert {:error, reason} = SessionIntake.guard_new_start([file], %{"continue" => "true"})
    assert reason =~ "neuem Start"
    assert reason =~ "#98"
  end

  test "CLI-Oberflaeche: session --help nennt Dateien und Optionen" do
    {out, 0} = KomkiCli.CLI.run(["session", "--help"])

    assert out =~ "FILE"
    assert out =~ "--room"
    assert out =~ "--db"
    assert out =~ "--decided-by"
  end

  test "CLI-Oberflaeche: Option ohne Wert -> Exit 2" do
    {out, 2} = KomkiCli.CLI.run(["session", "--db"])

    assert out =~ "braucht einen Wert"
  end

  # ========================================================================
  # Helfer
  # ========================================================================

  defp seed_term, do: @seed_path |> File.read!() |> JSON.decode!()

  defp write_source!(base, name, content) do
    dir = Path.join(base, "quellen")
    File.mkdir_p!(dir)
    path = Path.join(dir, name)
    File.write!(path, content)
    Config.canonical(path)
  end

  defp register_classified!(db, object_id, path, labels) do
    register_with_content_ref!(db, object_id, content_sha(path), labels)
  end

  # Nur fuer die B1-Regression: Altbestand mit Pfad-content_ref (#91).
  defp register_with_path_ref!(db, object_id, path, labels) do
    register_with_content_ref!(db, object_id, path, labels)
  end

  defp register_with_content_ref!(db, object_id, content_ref, labels) do
    {:ok, ref} = ObjectRef.parse(object_id <> "@v1")

    {:ok, _} =
      LabelStore.quarantine(db, ref, %{
        content_ref: content_ref,
        origin: "session-intake-test",
        decided_by: "nutzende-person",
        basis: "Testeingang (synthetisch)"
      })

    {:ok, _} = LabelStore.classify(db, ref, labels, "nutzende-person", "Testklassifikation")
  end

  defp content_sha(path) do
    {:ok, hex} = SessionIntake.sha256(path)
    "sha256:" <> hex
  end

  defp contract_json(bindings, eingangsrechte, opts) do
    %{
      "bindings" => Enum.sort(bindings),
      "auftrag" => "Sitzungsvorbereitung",
      "verantwortliche_person" => "nutzende-person",
      "eingangsrechte" => eingangsrechte,
      "purpose" => Keyword.get(opts, :purpose)
    }
  end

  defp load_room!(base, contract) do
    room_path = write_room!(base, contract)
    {:ok, compiled} = SessionIntake.load_registry(Path.join(base, "registry.db"))
    {:ok, room} = StartContract.load(room_path, compiled)
    room
  end

  defp compiled!(db) do
    {:ok, compiled} = SessionIntake.load_registry(db)
    compiled
  end

  defp write_contract_room!(base, bindings, eingangsrechte) do
    contract = contract_json(bindings, eingangsrechte, purpose: "sitzungsvorbereitung")
    write_room!(base, contract)
  end

  defp write_room!(base, contract) do
    dir = Path.join(base, "mediator")
    File.mkdir_p!(dir)
    path = Path.join(dir, "room.json")

    room =
      %{
        "schema" => "komki-mediator-room/1",
        "identity" => "nutzende-person",
        "workspace_id" => "ws-sitzung",
        "environment" => "lokal@1",
        "documents_dir" => "documents",
        "facts" => facts(Map.get(contract || %{}, "purpose")),
        "objects" => %{}
      }

    room =
      case contract do
        nil -> room
        contract -> Map.put(room, "contract", Map.delete(contract, "purpose"))
      end

    File.write!(path, JSON.encode!(room))
    path
  end

  defp facts(purpose) do
    base = %{
      "audit_path_ready" => %{
        "value" => true,
        "source" => "journal-verwaltung",
        "source_kind" => "technical"
      },
      "environment_observers_complete" => %{
        "value" => true,
        "source" => "umgebungs-verwaltung",
        "source_kind" => "assumption"
      },
      "has_operation_right" => %{
        "value" => true,
        "source" => "rechte-verwaltung",
        "source_kind" => "administered"
      },
      # Absichtlich true im Raum: der Intake muss diesen Wert je Objekt aus
      # den eingangsrechten ueberschreiben (S6a).
      "has_object_access_right" => %{
        "value" => true,
        "source" => "objekt-verwaltung",
        "source_kind" => "administered"
      },
      "workspace_scope_ok" => %{"value" => true, "source" => "test", "source_kind" => "test"}
    }

    if purpose do
      Map.put(base, "purpose", %{
        "value" => purpose,
        "source" => "auftrags-verwaltung",
        "source_kind" => "administered"
      })
    else
      base
    end
  end

  defp plan(db, base, room, files) do
    {:ok, compiled} = SessionIntake.load_registry(db)

    SessionIntake.plan(%{
      db: db,
      room: room,
      compiled: compiled,
      files: files,
      base_dir: base,
      pi_home: Path.join(base, "pi-home"),
      decided_by: "nutzende-person"
    })
  end

  defp stage!(intake) do
    assert :ok = SessionIntake.stage(intake)
  end

  # Steps-Testnaht: echte cfg, injizierter Doctor und tmux-Status.
  defp session_plan_opts(base, files, extra \\ %{}) do
    cfg = TestSupport.fixture_cfg(base)

    Map.merge(
      %{
        "files" => files,
        config: cfg,
        doctor: fn -> :ok end,
        start: fn -> :ok end,
        tmux_running?: fn -> false end
      },
      extra
    )
  end
end
