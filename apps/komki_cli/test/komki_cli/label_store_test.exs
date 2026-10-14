defmodule KomkiCli.LabelStoreTest do
  # async: false: der Sandbox-Test setzt KOMKI_HOME (globale Umgebung).
  use ExUnit.Case, async: false

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

  describe "Import (komki-label-store/1, Merge)" do
    test "Seed-Fixture importiert sauber: registry_id gesetzt, Zaehler stimmen", %{
      db: db,
      seed: seed
    } do
      assert {:ok, %{observers: 3, fact_fields: 2, environments: 1, bindings: 3}} =
               LabelStore.import_registry(db, seed)

      assert LabelStore.registry_id(db) == {:ok, "komki-synth-demo"}
    end

    test "Re-Import identischer Datei ist ein No-op (R.2.2: Bindung unveraenderlich)", %{
      db: db,
      seed: seed
    } do
      {:ok, _} = LabelStore.import_registry(db, seed)

      assert {:ok, %{observers: 0, fact_fields: 0, environments: 0, bindings: 0}} =
               LabelStore.import_registry(db, seed)
    end

    test "abweichender Bindungsinhalt verweigert den Import", %{db: db, seed: seed} do
      {:ok, _} = LabelStore.import_registry(db, seed)

      seed2 = seed_seed(seed, ["bindings", "ratsarbeit@1", "bezeichnung"], "Anderer Text")

      assert {:error, reason} = LabelStore.import_registry(db, seed2)
      assert reason =~ "unveraenderlich"
      assert reason =~ "ratsarbeit@1"
    end

    test "unbekanntes Top-Level-Feld verweigert (geschlossenes Schema)", %{db: db, seed: seed} do
      seed2 = Map.put(seed, "extra-feld", "boom")

      assert {:error, reason} = LabelStore.import_registry(db, seed2)
      assert reason =~ "unknown_field"
    end

    test "B.4-ungueltige Expression propagiert den Engine-Compile-Fehler (Code + Pfad)", %{
      db: db,
      seed: seed
    } do
      seed2 =
        seed_seed(seed, ["bindings", "ratsarbeit@1", "operations", "admit"], %{"not" => true})

      assert {:error, reason} = LabelStore.import_registry(db, seed2)
      assert reason =~ "unsupported_expression"
      assert reason =~ "$.bindings"
    end

    test "reader ausserhalb des Beobachterraums verweigert (unknown_observer)", %{
      db: db,
      seed: seed
    } do
      seed2 =
        seed_seed(seed, ["bindings", "ratsarbeit@1", "readers"], [
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

      seed2 = seed_seed(seed, ["registry_id"], "komki-andere-demo")

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
               quarantine(db, "brief-4711", "v1")

      assert state == %{
               object: "brief-4711@v1",
               classification: "quarantine",
               labels: []
             }

      assert {:ok, %{object: object, decisions: [d | _]}} =
               LabelStore.show_object(db, "brief-4711", "v1")

      assert object.classification == "quarantine"
      assert d.classification == "quarantine"
      assert d.labels == []
      assert d.decided_by == "nutzende-person"
      assert d.basis != ""
    end

    test "Quarantäne auf neuem Objekt verlangt content_ref und origin", %{db: db} do
      {:ok, _} = import_seed(db)

      assert {:error, reason} =
               LabelStore.quarantine(db, "brief-4711", "v1", %{
                 content_ref: nil,
                 origin: nil,
                 decided_by: "nutzende-person",
                 basis: "Eingangspruefung"
               })

      assert reason =~ "--content-ref und --origin"
    end

    test "Rueckholung bestehenden Objekts in Quarantäne haengt decisions-Eintrag an", %{
      db: db
    } do
      {:ok, _} = import_seed(db)
      {:ok, _} = quarantine(db, "brief-4711", "v1")
      {:ok, _} = quarantine(db, "brief-4711", "v1")

      assert {:ok, %{decisions: [d1, d2]}} = LabelStore.show_object(db, "brief-4711", "v1")
      assert d1.classification == "quarantine" and d2.classification == "quarantine"
      assert d2.labels == []
    end

    test "abweichende content_ref bei bestehendem Objekt verweigert (neue Objektversion)", %{
      db: db
    } do
      {:ok, _} = import_seed(db)
      {:ok, _} = quarantine(db, "brief-4711", "v1")

      assert {:error, reason} =
               LabelStore.quarantine(db, "brief-4711", "v1", %{
                 content_ref: @other_content_ref,
                 origin: nil,
                 decided_by: "nutzende-person",
                 basis: "Erneuter Eingang"
               })

      assert reason =~ "neue Inhaltsfassung braucht neue Objektversion"
    end

    test " Erstklassifikation mit Label setzt classified (Historie 2 Eintraege)", %{db: db} do
      {:ok, _} = import_seed(db)
      {:ok, _} = quarantine(db, "brief-4711", "v1")

      assert {:ok, state} = classify(db, "brief-4711", "v1", ["ratsarbeit@1"])

      assert state == %{
               object: "brief-4711@v1",
               classification: "classified",
               labels: ["ratsarbeit@1"]
             }

      assert {:ok, %{decisions: [d1, d2]}} = LabelStore.show_object(db, "brief-4711", "v1")
      assert d1.classification == "quarantine"
      assert d2.classification == "classified"
      assert d2.labels == ["ratsarbeit@1"]
    end

    test "ausdruecklich leeres Label ist classified mit [], NICHT Quarantäne (R.2.5)", %{db: db} do
      {:ok, _} = import_seed(db)
      {:ok, _} = quarantine(db, "brief-4711", "v1")

      assert {:ok, state} = classify(db, "brief-4711", "v1", [])
      assert state.classification == "classified"
      assert state.labels == []
    end

    test "classify unbekanntes Objekt verweigert (Exit-2-Fehler)", %{db: db} do
      {:ok, _} = import_seed(db)

      assert {:error, reason} = classify(db, "brief-4711", "v1", ["ratsarbeit@1"])
      assert reason =~ "unbekanntes Objekt"
      assert reason =~ "komki label quarantine"
    end

    test "classify mit unbekannter Bindung verweigert", %{db: db} do
      {:ok, _} = import_seed(db)
      {:ok, _} = quarantine(db, "brief-4711", "v1")

      assert {:error, reason} = classify(db, "brief-4711", "v1", ["fremd@9"])
      assert reason =~ "unbekannte Bindung"
    end

    test "doppelte --label verweigert", %{db: db} do
      {:ok, _} = import_seed(db)
      {:ok, _} = quarantine(db, "brief-4711", "v1")

      assert {:error, reason} =
               classify(db, "brief-4711", "v1", ["ratsarbeit@1", "ratsarbeit@1"])

      assert reason =~ "doppelte Bindung"
    end

    test "classify mit unbekanntem Beobachter verweigert", %{db: db} do
      {:ok, _} = import_seed(db)
      {:ok, _} = quarantine(db, "brief-4711", "v1")

      assert {:error, reason} =
               LabelStore.classify(
                 db,
                 "brief-4711",
                 "v1",
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

    test "Export entspricht der Engine-Projektion des Seeds", %{db: db, seed: seed} do
      {:ok, _} = import_seed(db)

      assert {:ok, json} = LabelStore.export(db)

      expected = %{
        "schema" => "komki-registry/1",
        "registry_id" => seed["registry_id"],
        "observers" => seed["observers"],
        "fact_fields" => seed["fact_fields"],
        "environments" => seed["environments"],
        "bindings" =>
          Map.new(seed["bindings"], fn {id, binding} ->
            {id,
             %{
               "readers" => binding["readers"],
               "operations" => binding["operations"],
               "relaxation_authorities" => binding["relaxation_authorities"]
             }}
          end)
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
  # Sandbox-Schreibhoheit (R.2.1-Mechanik; Labels ausserhalb des
  # Agenten-Schreibbereichs)
  # ========================================================================

  describe "Sandbox-Schreibhoheit" do
    test "Default-DB liegt an der Basis-Wurzel, nicht in pi-home/Scratch", %{} do
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

  # deep-put (Fixtures per Pfadliste veraendern).
  defp seed_seed(map, [key], value), do: Map.put(map, key, value)

  defp seed_seed(map, [key | rest], value),
    do: Map.put(map, key, seed_seed(Map.fetch!(map, key), rest, value))

  defp quarantine(db, object_id, version) do
    LabelStore.quarantine(db, object_id, version, %{
      content_ref: @probe_content_ref,
      origin: "synthetische Probe",
      decided_by: "nutzende-person",
      basis: "Eingangspruefung (Quelle: synthetische Probe, Ticket #91)"
    })
  end

  defp classify(db, object_id, version, labels) do
    LabelStore.classify(
      db,
      object_id,
      version,
      labels,
      "nutzende-person",
      "Erstklassifikation Rueckschluss: nichts oeffentliches (Quelle: synthetische Probe)"
    )
  end
end
