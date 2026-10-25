defmodule KomkiCli.LabelStoreTest do
  # async: false: der Sandbox-Test setzt KOMKI_HOME (globale Umgebung).
  use ExUnit.Case, async: false

  alias Exqlite.Sqlite3
  alias KomkiCli.{LabelStore, Profile, TestSupport}
  alias KomkiPolicy.Registry

  @seed_path Path.join([:code.priv_dir(:komki_cli), "fixtures", "registry-seed.json"])

  # Zwei verschiedene Inhaltsreferenzen fuer Neue-Objekt/Wechsel-Fälle.
  @probe_content_ref "/tmp/komki-fixture/probe.docx"
  @other_content_ref "/tmp/komki-fixture/anders.docx"

  setup do
    db = Path.join(TestSupport.tmp_area!("komki-store"), "registry.db")
    {:ok, db: db, seed: JSON.decode!(File.read!(@seed_path))}
  end

  describe "Import (komki-label-store/2, Merge)" do
    test "Seed-Fixture importiert sauber: registry_id gesetzt, Zaehler stimmen", %{
      db: db,
      seed: seed
    } do
      assert {:ok, %{observers: 3, fact_fields: 2, environments: 1, bindings: 3}} =
               LabelStore.import_registry(db, seed)

      assert LabelStore.registry_id(db) == {:ok, "komki-synth-demo"}
    end

    test "Re-Import identischer Datei ist ein No-op (R.2.2: Bindung unveränderlich)", %{
      db: db,
      seed: seed
    } do
      {:ok, _} = LabelStore.import_registry(db, seed)

      assert {:ok, %{observers: 0, fact_fields: 0, environments: 0, bindings: 0}} =
               LabelStore.import_registry(db, seed)
    end

    test "abweichender Bindungsinhalt verweigert den Import", %{db: db, seed: seed} do
      {:ok, _} = LabelStore.import_registry(db, seed)

      seed2 = deep_put(seed, ["bindings", "ratsarbeit@1", "bezeichnung"], "Anderer Text")

      assert {:error, reason} = LabelStore.import_registry(db, seed2)
      assert reason =~ "unveränderlich"
      assert reason =~ "ratsarbeit@1"
    end

    test "unbekanntes Top-Level-Feld verweigert (geschlossenes Schema)", %{db: db, seed: seed} do
      seed2 = Map.put(seed, "extra-feld", "boom")

      assert {:error, reason} = LabelStore.import_registry(db, seed2)
      assert reason =~ "unknown_field"
    end

    test "B.4-ungültige Expression propagiert den Engine-Compile-Fehler (Code + Pfad)", %{
      db: db,
      seed: seed
    } do
      seed2 =
        deep_put(seed, ["bindings", "ratsarbeit@1", "operations", "admit"], %{"not" => true})

      assert {:error, reason} = LabelStore.import_registry(db, seed2)
      assert reason =~ "unsupported_expression"
      assert reason =~ "$.bindings"
    end

    test "reader außerhalb des Beobachterraums verweigert (unknown_observer)", %{
      db: db,
      seed: seed
    } do
      seed2 =
        deep_put(seed, ["bindings", "ratsarbeit@1", "readers"], [
          "fraktionskollege",
          "lokale-verarbeitung",
          "nutzende-person",
          "fremder-dienst"
        ])

      assert {:error, reason} = LabelStore.import_registry(db, seed2)
      assert reason =~ "unknown_observer"
    end

    test "registry_id-Wechsel an importierten Store verweigert", %{db: db, seed: seed} do
      {:ok, _} = LabelStore.import_registry(db, seed)

      seed2 = deep_put(seed, ["registry_id"], "komki-andere-demo")

      assert {:error, reason} = LabelStore.import_registry(db, seed2)
      assert reason =~ "registry_id_mismatch"
    end
  end

  # ========================================================================
  # Objekte und Entscheidungen (R.2.1/R.2.5)
  # ========================================================================

  describe "Objekte und Entscheidungen" do
    test "Quarantäne registriert: classification quarantine,Labels [], Historie 1 Eintrag", %{
      db: db
    } do
      {:ok, _} = import_seed(db)

      assert {:ok, state} =
               quarantine(db, ref("brief-4711", "v1"))

      assert state == %{
               object: "brief-4711@v1",
               classification: "quarantine",
               labels: []
             }

      assert {:ok, %{object: object, decisions: [d | _]}} =
               LabelStore.show_object(db, ref("brief-4711", "v1"))

      assert object.classification == "quarantine"
      assert d.classification == "quarantine"
      assert d.labels == []
      assert d.decided_by == "nutzende-person"
      assert d.basis != ""
    end

    test "Quarantäne auf neuem Objekt verlangt content_ref und origin", %{db: db} do
      {:ok, _} = import_seed(db)

      assert {:error, reason} =
               LabelStore.quarantine(db, ref("brief-4711", "v1"), %{
                 content_ref: nil,
                 origin: nil,
                 decided_by: "nutzende-person",
                 basis: "Eingangspruefung"
               })

      assert reason =~ "--content-ref und --origin"
    end

    test "Rückholung bestehenden Objekts in Quarantäne haengt decisions-Eintrag an", %{
      db: db
    } do
      {:ok, _} = import_seed(db)
      {:ok, _} = quarantine(db, ref("brief-4711", "v1"))
      {:ok, _} = quarantine(db, ref("brief-4711", "v1"))

      assert {:ok, %{decisions: [d1, d2]}} =
               LabelStore.show_object(db, ref("brief-4711", "v1"))

      assert d1.classification == "quarantine" and d2.classification == "quarantine"
      assert d2.labels == []
    end

    test "abweichende content_ref bei bestehendem Objekt verweigert (neue Objektversion)", %{
      db: db
    } do
      {:ok, _} = import_seed(db)
      {:ok, _} = quarantine(db, ref("brief-4711", "v1"))

      assert {:error, reason} =
               LabelStore.quarantine(db, ref("brief-4711", "v1"), %{
                 content_ref: @other_content_ref,
                 origin: nil,
                 decided_by: "nutzende-person",
                 basis: "Erneuter Eingang"
               })

      assert reason =~ "neue Inhaltsfassung braucht neue Objektversion"
    end

    test " Erstklassifikation mit Label setzt classified (Historie 2 Einträge)", %{db: db} do
      {:ok, _} = import_seed(db)
      {:ok, _} = quarantine(db, ref("brief-4711", "v1"))

      assert {:ok, state} = classify(db, ref("brief-4711", "v1"), ["ratsarbeit@1"])

      assert state == %{
               object: "brief-4711@v1",
               classification: "classified",
               labels: ["ratsarbeit@1"]
             }

      assert {:ok, %{decisions: [d1, d2]}} =
               LabelStore.show_object(db, ref("brief-4711", "v1"))

      assert d1.classification == "quarantine"
      assert d2.classification == "classified"
      assert d2.labels == ["ratsarbeit@1"]
    end

    test "ausdrücklich leeres Label ist classified mit [], NICHT Quarantäne (R.2.5)", %{db: db} do
      {:ok, _} = import_seed(db)
      {:ok, _} = quarantine(db, ref("brief-4711", "v1"))

      assert {:ok, state} = classify(db, ref("brief-4711", "v1"), [])
      assert state.classification == "classified"
      assert state.labels == []
    end

    test "classify unbekanntes Objekt verweigert (Exit-2-Fehler)", %{db: db} do
      {:ok, _} = import_seed(db)

      assert {:error, reason} = classify(db, ref("brief-4711", "v1"), ["ratsarbeit@1"])
      assert reason =~ "unbekanntes Objekt"
      assert reason =~ "komki label quarantine"
    end

    test "classify mit unbekannter Bindung verweigert", %{db: db} do
      {:ok, _} = import_seed(db)
      {:ok, _} = quarantine(db, ref("brief-4711", "v1"))

      assert {:error, reason} = classify(db, ref("brief-4711", "v1"), ["fremd@9"])
      assert reason =~ "unbekannte Bindung"
    end

    test "doppelte --label verweigert", %{db: db} do
      {:ok, _} = import_seed(db)
      {:ok, _} = quarantine(db, ref("brief-4711", "v1"))

      assert {:error, reason} =
               classify(db, ref("brief-4711", "v1"), ["ratsarbeit@1", "ratsarbeit@1"])

      assert reason =~ "doppelte Bindung"
    end

    test "classify mit unbekanntem Beobachter verweigert", %{db: db} do
      {:ok, _} = import_seed(db)
      {:ok, _} = quarantine(db, ref("brief-4711", "v1"))

      assert {:error, reason} =
               LabelStore.classify(
                 db,
                 ref("brief-4711", "v1"),
                 ["ratsarbeit@1"],
                 "unbekannt-wer",
                 "Basis"
               )

      assert reason =~ "unbekannter Beobachter"
    end
  end

  # ========================================================================
  # Γ-Export
  # ========================================================================

  describe "Γ-Export" do
    test "Export laesst sich von der Engine kompilieren (CONTRACT § 2.1)", %{db: db} do
      {:ok, _} = import_seed(db)

      assert {:ok, json} = LabelStore.export(db)

      assert {:ok, _compiled} = Registry.compile(JSON.decode!(json))
    end

    # Unabhaengiges Orakel: das erwartete komki-registry/2 steht als Literal
    # hier (aus der Seed-Fixture abgeleitet und eingefroren), NICHT durch
    # erneute Anwendung der Store-Projektionslogik — das Exportergebnis
    # belegt sich also nicht selbst.
    test "Export entspricht dem erwarteten komki-registry/2 (unabhaengiges Orakel)", %{db: db} do
      {:ok, _} = import_seed(db)

      assert {:ok, json} = LabelStore.export(db)

      expected = %{
        "schema" => "komki-registry/2",
        "registry_id" => "komki-synth-demo",
        "observers" => ["fraktionskollege", "lokale-verarbeitung", "nutzende-person"],
        "fact_fields" => %{"purpose" => "string", "workspace_scope_ok" => "boolean"},
        "environments" => %{
          "lokal@1" => %{"observers" => ["lokale-verarbeitung", "nutzende-person"]}
        },
        "bindings" => %{
          "ratsarbeit@1" => %{
            "readers" => ["fraktionskollege", "lokale-verarbeitung", "nutzende-person"],
            "operations" => %{
              "admit" => %{
                "all" => [
                  %{"eq" => ["purpose", "sitzungsvorbereitung"]},
                  %{"eq" => ["workspace_scope_ok", true]}
                ]
              }
            },
            "relaxation_authorities" => []
          },
          "lizenz-namensnennung@1" => %{
            "readers" => ["fraktionskollege", "lokale-verarbeitung", "nutzende-person"],
            "operations" => %{"admit" => true},
            "relaxation_authorities" => []
          },
          "vorfaelle-archiv@1" => %{
            "readers" => ["nutzende-person"],
            "operations" => %{"start" => true},
            "relaxation_authorities" => []
          }
        }
      }

      assert JSON.decode!(json) == expected
    end

    test "Export ist byte-deterministisch", %{db: db} do
      {:ok, _} = import_seed(db)

      assert {:ok, json1} = LabelStore.export(db)
      assert {:ok, json2} = LabelStore.export(db)
      assert json1 == json2
      assert String.ends_with?(json1, "\n")
    end

    test "Export vor jedem Import verweigert", %{db: db} do
      assert {:error, reason} = LabelStore.export(db)
      assert reason =~ "Registry leer"
    end
  end

  # ========================================================================
  # Lockerungsbefugnisse (R.2.2, strukturiert; Γ emittiert [], Ticket #109)
  # ========================================================================

  describe "Strukturierte Lockerungsbefugnisse (R.2.2)" do
    # Der Seed traegt genau diesen Eintrag auf ratsarbeit@1.
    @seed_entry %{
      "authority" => "nutzende-person",
      "restriction" => "auflagen",
      "output" => "sitzungsmappe"
    }

    test "gueltiger Eintrag importiert und via show binding sichtbar", %{db: db} do
      {:ok, _} = import_seed(db)

      assert {:ok, binding} = LabelStore.show_binding(db, "ratsarbeit@1")
      assert binding.relaxation_authorities == [@seed_entry]
    end

    test "flache String-Liste verweigert (strukturierte Einträge nötig)", %{db: db, seed: seed} do
      seed2 =
        deep_put(seed, ["bindings", "ratsarbeit@1", "relaxation_authorities"], ["nutzende-person"])

      assert {:error, reason} = LabelStore.import_registry(db, seed2)
      assert reason =~ "relaxation_authorities"
      assert reason =~ "erwartet Objekt"
    end

    test "authority außerhalb des Beobachterraums verweigert", %{db: db, seed: seed} do
      entry = Map.put(@seed_entry, "authority", "fremder-dienst")
      seed2 = deep_put(seed, ["bindings", "ratsarbeit@1", "relaxation_authorities"], [entry])

      assert {:error, reason} = LabelStore.import_registry(db, seed2)
      assert reason =~ "unbekannter Beobachter"
      assert reason =~ "fremder-dienst"
    end

    test "restriction außerhalb der drei Einschraenkungskomponenten verweigert", %{
      db: db,
      seed: seed
    } do
      entry = Map.put(@seed_entry, "restriction", "labels")
      seed2 = deep_put(seed, ["bindings", "ratsarbeit@1", "relaxation_authorities"], [entry])

      assert {:error, reason} = LabelStore.import_registry(db, seed2)
      assert reason =~ "restriction"
      assert reason =~ ~s("labels")
    end

    test "doppelte Einträge verweigert (nicht stillschweigend vereinzelt)", %{
      db: db,
      seed: seed
    } do
      seed2 =
        deep_put(seed, ["bindings", "ratsarbeit@1", "relaxation_authorities"], [
          @seed_entry,
          @seed_entry
        ])

      assert {:error, reason} = LabelStore.import_registry(db, seed2)
      assert reason =~ "doppelte Lockerungsbefugnis"
    end

    test "Γ-Export emittiert [], obwohl der Store Einträge hält (Ticket #109)", %{
      db: db
    } do
      {:ok, _} = import_seed(db)

      assert {:ok, json} = LabelStore.export(db)
      decoded = JSON.decode!(json)
      assert decoded["bindings"]["ratsarbeit@1"]["relaxation_authorities"] == []
      assert {:ok, _compiled} = Registry.compile(decoded)
    end
  end

  # ========================================================================
  # Beobachtertypen und Entscheider-Gate (R.2.5)
  # ========================================================================

  describe "Beobachtertypen und Entscheider-Gate (R.2.5)" do
    test "Verarbeitungsdomäne als decided-by verweigert: nur eine Person entscheidet", %{
      db: db
    } do
      {:ok, _} = import_seed(db)
      {:ok, _} = quarantine(db, ref("brief-4711", "v1"))

      assert {:error, reason} =
               LabelStore.classify(
                 db,
                 ref("brief-4711", "v1"),
                 [],
                 "lokale-verarbeitung",
                 "Automatisch klassifiziert durch Verarbeitungsdomäne"
               )

      assert reason =~ "R.2.5"
      assert reason =~ "Verarbeitungsdomäne"

      assert {:error, reason} =
               LabelStore.quarantine(db, ref("protokoll-9", "v1"), %{
                 content_ref: @probe_content_ref,
                 origin: "synthetische Probe",
                 decided_by: "lokale-verarbeitung",
                 basis: "Eingang durch Domaene"
               })

      assert reason =~ "R.2.5"
      assert reason =~ "Verarbeitungsdomäne"
    end

    test "Store ohne observer_types-Einträge verweigert Entscheidungen (fail-closed)", %{
      db: db
    } do
      {:ok, _} = import_seed(db)
      {:ok, _} = quarantine(db, ref("brief-4711", "v1"))

      {:ok, conn} = Sqlite3.open(db)
      :ok = Sqlite3.execute(conn, "DELETE FROM observer_types")
      _ = Sqlite3.close(conn)

      assert {:error, reason} =
               LabelStore.classify(
                 db,
                 ref("brief-4711", "v1"),
                 ["ratsarbeit@1"],
                 "nutzende-person",
                 "Basis (Quelle: synthetische Probe)"
               )

      assert reason =~ "R.2.5"
      assert reason =~ "ohne Beobachtertyp"
    end

    test "observer_types mit fehlendem Beobachter verweigert (Schluesseldeckung)", %{
      db: db,
      seed: seed
    } do
      seed2 =
        deep_put(
          seed,
          ["observer_types"],
          Map.delete(seed["observer_types"], "lokale-verarbeitung")
        )

      assert {:error, reason} = LabelStore.import_registry(db, seed2)
      assert reason =~ "$.observer_types"
      assert reason =~ "fehlt" or reason =~ "fehlend"
    end

    test "observer_types mit unbekanntem Typ verweigert", %{db: db, seed: seed} do
      seed2 = deep_put(seed, ["observer_types", "lokale-verarbeitung"], "agent")

      assert {:error, reason} = LabelStore.import_registry(db, seed2)
      assert reason =~ ~s(erwartet "person" oder "processing_domain")
    end

    test "Wechsel eines Beobachtertyps verweigert (Typen sind unveränderlich)", %{
      db: db,
      seed: seed
    } do
      {:ok, _} = LabelStore.import_registry(db, seed)

      seed2 = deep_put(seed, ["observer_types", "nutzende-person"], "processing_domain")

      assert {:error, reason} = LabelStore.import_registry(db, seed2)
      assert reason =~ "Beobachtertyp unveränderlich"
      assert reason =~ "person != processing_domain"
    end
  end

  # ========================================================================
  # Sandbox-Schreibhoheit (R.2.1-Mechanik; Labels ausserhalb des
  # Agenten-Schreibbereichs)
  # ========================================================================

  describe "Sandbox-Schreibhoheit" do
    test "Default-DB liegt am Basis-Root, nicht in pi-home/Scratch", %{} do
      area = TestSupport.tmp_area!("komki-scope")
      System.put_env("KOMKI_HOME", area)

      on_exit(fn -> System.delete_env("KOMKI_HOME") end)

      cfg = TestSupport.fixture_cfg(area)
      db = LabelStore.default_path()

      assert Path.dirname(db) == cfg.base_dir
      assert Path.basename(db) == "registry.db"
      refute String.starts_with?(db, cfg.pi_home)
      refute String.starts_with?(db, Path.join([cfg.base_dir, "runs"]))
    end

    test "keine file-write*-Regel des Profils deckt den Default-DB-Pfad", %{} do
      area = TestSupport.tmp_area!("komki-scope-profile")
      System.put_env("KOMKI_HOME", area)

      on_exit(fn -> System.delete_env("KOMKI_HOME") end)

      cfg = TestSupport.fixture_cfg(area)
      db = LabelStore.default_path()
      profile_text = Profile.generate(cfg, Path.join([cfg.base_dir, "runs", "probe"]))

      write_paths =
        profile_text
        |> String.split("\n")
        |> Enum.filter(&String.contains?(&1, "(allow file-write*"))
        |> Enum.flat_map(fn line ->
          [captured | _] = Regex.run(~r/"([^"]+)"/, line)
          [captured]
        end)
        |> Enum.uniq()

      assert write_paths != []

      Enum.each(write_paths, fn path ->
        covered? = db == path or String.starts_with?(db, path <> "/")
        refute covered?, "Sandbox file-write* deckt die Registry-DB: " <> path
      end)
    end
  end

  # ========================================================================
  # Helfer
  # ========================================================================

  defp import_seed(db) do
    LabelStore.import_registry(db, seed_fixture())
  end

  defp seed_fixture, do: JSON.decode!(File.read!(@seed_path))

  # deep-put: Fixtures per Pfadliste veraendern.
  defp deep_put(map, [key], value), do: Map.put(map, key, value)

  defp deep_put(map, [key | rest], value),
    do: Map.put(map, key, deep_put(Map.fetch!(map, key), rest, value))

  defp quarantine(db, %LabelStore.ObjectRef{} = object_ref) do
    LabelStore.quarantine(db, object_ref, %{
      content_ref: @probe_content_ref,
      origin: "synthetische Probe",
      decided_by: "nutzende-person",
      basis: "Eingangspruefung (Quelle: synthetische Probe, Ticket #91)"
    })
  end

  defp classify(db, %LabelStore.ObjectRef{} = object_ref, labels) do
    LabelStore.classify(
      db,
      object_ref,
      labels,
      "nutzende-person",
      "Erstklassifikation Rueckschluss: nichts oeffentliches (Quelle: synthetische Probe)"
    )
  end

  # Objektreferenz OBJ@VER als Struct (KomkiCli.LabelStore.ObjectRef).
  defp ref(object_id, version),
    do: %LabelStore.ObjectRef{object_id: object_id, version: version}
end
