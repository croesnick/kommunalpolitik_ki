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

  # Vorlagen-Upgrade (Ticket #354, ADR 0007): Nur eine fruehere
  # mitgelieferte Fassung, die der Import ausdruecklich als ersetzbar nennt,
  # weicht der aktuellen. Alles andere bleibt unveraenderlich (R.2.2).
  describe "Vorlagen-Upgrade" do
    setup %{seed: seed} do
      [{id, binding} | _] = Enum.sort(seed["bindings"])
      old = Map.put(binding, "bezeichnung", binding["bezeichnung"] <> " (alt)")
      old_seed = put_in(seed, ["bindings", id], old)
      %{id: id, old_seed: old_seed, old: old}
    end

    test "fruehere Fassung wird ersetzt und der Uebergang festgehalten", ctx do
      assert {:ok, _} = LabelStore.import_registry(ctx.db, ctx.old_seed)

      upgrades = %{ctx.id => [LabelStore.binding_fingerprint(ctx.old)]}
      assert {:ok, _} = LabelStore.import_registry(ctx.db, ctx.seed, upgrades: upgrades)

      # Danach ist die aktuelle Fassung im Store: ein Re-Import ist ein No-op.
      assert {:ok, %{bindings: 0}} = LabelStore.import_registry(ctx.db, ctx.seed)

      assert {:ok, [upgrade]} = LabelStore.binding_upgrades(ctx.db)
      assert upgrade["binding"] == ctx.id
      assert upgrade["from_sha256"] == LabelStore.binding_fingerprint(ctx.old)
      assert upgrade["to_sha256"] == LabelStore.binding_fingerprint(ctx.seed["bindings"][ctx.id])
    end

    test "ohne Upgrade-Angabe bleibt die Bindung unveränderlich (komki label import)", ctx do
      assert {:ok, _} = LabelStore.import_registry(ctx.db, ctx.old_seed)
      assert {:error, reason} = LabelStore.import_registry(ctx.db, ctx.seed)
      assert reason =~ "Bindung unveränderlich: " <> ctx.id
      assert {:ok, []} = LabelStore.binding_upgrades(ctx.db)
    end

    test "eine selbst veränderte Fassung ersetzt das Upgrade nicht", ctx do
      own = put_in(ctx.old_seed, ["bindings", ctx.id, "bezeichnung"], "eigene Fassung")
      assert {:ok, _} = LabelStore.import_registry(ctx.db, own)

      upgrades = %{ctx.id => [LabelStore.binding_fingerprint(ctx.old)]}
      assert {:error, reason} = LabelStore.import_registry(ctx.db, ctx.seed, upgrades: upgrades)
      assert reason =~ "Bindung unveränderlich: " <> ctx.id
      assert {:ok, []} = LabelStore.binding_upgrades(ctx.db)
    end
  end

  # Ticket #606, R.2.5: Eine freigegebene Importregel ordnet neue Dateien
  # aus einer belegten Quelle ein, wenn komki ein Merkmal selbst prüft.
  describe "Importregeln" do
    @ordner "/tmp/komki-fixture/ratsinfo"

    defp regel(overrides \\ %{}) do
      Map.merge(
        %{
          "id" => "ris-protokolle",
          "ordner" => @ordner,
          "typen" => ["pdf", "md"],
          "max_bytes" => 1_000,
          "labels" => ["lizenz-namensnennung@1"],
          "decided_by" => "nutzende-person",
          "basis" => "Öffentliche Protokolle aus dem RIS-Download",
          "gueltig_bis" => "2099-12-31"
        },
        overrides
      )
    end

    @heute ~D[2026-11-17]

    test "Herkunft allein reicht nicht: ohne Dateityp keine Regel", %{db: db} do
      {:ok, _} = import_seed(db)
      assert {:error, reason} = LabelStore.add_rule(db, regel(%{"typen" => []}))
      assert reason =~ "Herkunft allein reicht nicht"
    end

    test "nur eine Person gibt eine Regel frei, nur bekannte Bindungen", %{db: db} do
      {:ok, _} = import_seed(db)

      assert {:error, reason} =
               LabelStore.add_rule(db, regel(%{"decided_by" => "lokale-verarbeitung"}))

      assert reason =~ "Verarbeitungsdomäne"
      assert {:error, _} = LabelStore.add_rule(db, regel(%{"labels" => ["gibt-es-nicht@1"]}))
      assert {:error, _} = LabelStore.add_rule(db, regel(%{"ordner" => "relativ/pfad"}))
    end

    test "passt nur bei Quelle, Endung, Größe und Frist", %{db: db} do
      {:ok, _} = import_seed(db)
      assert {:ok, %{version: 1}} = LabelStore.add_rule(db, regel())

      assert {:ok, %{id: "ris-protokolle"}} =
               LabelStore.rule_for(db, @ordner <> "/top-7.pdf", 500, @heute)

      # Andere Endung, zu groß, anderer Ordner, Präfix ohne Trennzeichen, abgelaufen.
      assert :none = LabelStore.rule_for(db, @ordner <> "/top-7.docx", 500, @heute)
      assert :none = LabelStore.rule_for(db, @ordner <> "/top-7.pdf", 5_000, @heute)
      assert :none = LabelStore.rule_for(db, "/tmp/komki-fixture/andere/top-7.pdf", 500, @heute)
      assert :none = LabelStore.rule_for(db, @ordner <> "-alt/top-7.pdf", 500, @heute)
      assert :none = LabelStore.rule_for(db, @ordner <> "/top-7.pdf", 500, ~D[2100-01-01])
    end

    test "neue Fassung ersetzt die alte, Widerruf beendet die Regel", %{db: db} do
      {:ok, _} = import_seed(db)
      {:ok, _} = LabelStore.add_rule(db, regel())
      assert {:ok, %{version: 2}} = LabelStore.add_rule(db, regel(%{"typen" => ["md"]}))

      # Fassung 2 kennt kein PDF mehr.
      assert :none = LabelStore.rule_for(db, @ordner <> "/top-7.pdf", 500, @heute)
      assert {:ok, %{version: 2}} = LabelStore.rule_for(db, @ordner <> "/top-7.md", 500, @heute)

      assert {:ok, %{widerrufen_am: am}} = LabelStore.revoke_rule(db, "ris-protokolle")
      assert is_binary(am)
      assert :none = LabelStore.rule_for(db, @ordner <> "/top-7.md", 500, @heute)
      assert {:error, _} = LabelStore.revoke_rule(db, "ris-protokolle")
      assert {:ok, [_v1, _v2]} = LabelStore.rules(db)
    end

    test "zwei passende Regeln: keine ordnet ein (die Person entscheidet)", %{db: db} do
      {:ok, _} = import_seed(db)
      {:ok, _} = LabelStore.add_rule(db, regel())
      {:ok, _} = LabelStore.add_rule(db, regel(%{"id" => "ris-zweite"}))
      assert :none = LabelStore.rule_for(db, @ordner <> "/top-7.pdf", 500, @heute)
    end

    test "Einordnung durch die Regel steht im Ledger mit Regel und Fassung", %{db: db} do
      {:ok, _} = import_seed(db)
      {:ok, rule} = LabelStore.add_rule(db, regel())
      {:ok, _} = quarantine(db, ref("protokoll-7", "v1"))

      assert {:ok, %{classification: "classified", labels: ["lizenz-namensnennung@1"]}} =
               LabelStore.classify_by_rule(db, ref("protokoll-7", "v1"), rule)

      assert {:ok, %{decisions: decisions}} = LabelStore.show_object(db, ref("protokoll-7", "v1"))
      last = List.last(decisions)
      assert last.decided_by == "nutzende-person"
      assert last.basis =~ "Importregel ris-protokolle@1"

      {:ok, conn} = Sqlite3.open(db)
      {:ok, stmt} = Sqlite3.prepare(conn, "SELECT rule_id, rule_version FROM rule_decisions")
      assert {:row, ["ris-protokolle", 1]} = Sqlite3.step(conn, stmt)
      Sqlite3.close(conn)
    end
  end

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

    # Unabhaengiges Orakel: das erwartete komki-registry/3 steht als Literal
    # hier (aus der Seed-Fixture abgeleitet und eingefroren), NICHT durch
    # erneute Anwendung der Store-Projektionslogik — das Exportergebnis
    # belegt sich also nicht selbst.
    test "Export entspricht dem erwarteten komki-registry/3 (unabhaengiges Orakel)", %{db: db} do
      {:ok, _} = import_seed(db)

      assert {:ok, json} = LabelStore.export(db)

      expected = %{
        "schema" => "komki-registry/3",
        "registry_id" => "komki-synth-demo",
        "observers" => ["fraktionskollege", "lokale-verarbeitung", "nutzende-person"],
        "observer_types" => %{
          "fraktionskollege" => "person",
          "lokale-verarbeitung" => "processing_domain",
          "nutzende-person" => "person"
        },
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
            "relaxation_authorities" => [
              %{
                "authority" => "nutzende-person",
                "restriction" => "auflagen",
                "output" => "sitzungsmappe"
              }
            ]
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
  # Lockerungsbefugnisse (R.2.2, strukturiert; Γ-Export seit #423)
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

    test "Γ-Export traegt die strukturierten Eintraege (seit #423; vorher [] bis #109)", %{
      db: db
    } do
      {:ok, _} = import_seed(db)

      assert {:ok, json} = LabelStore.export(db)
      decoded = JSON.decode!(json)

      assert decoded["bindings"]["ratsarbeit@1"]["relaxation_authorities"] == [
               %{
                 "authority" => "nutzende-person",
                 "restriction" => "auflagen",
                 "output" => "sitzungsmappe"
               }
             ]

      # Der exportierte Γ kompiliert: Die Engine validiert die Eintraege
      # gegen das geschlossene Vokabular (CONTRACT § 2.1).
      assert {:ok, _compiled} = Registry.compile(decoded)
    end

    test "Eintrag mit unbekannter Ausgabeart ueberlebt den Store, aber nicht die Engine-Projektion",
         %{
           db: db,
           seed: seed
         } do
      entry = Map.put(@seed_entry, "output", "unbekannte-ausgabe")
      seed2 = deep_put(seed, ["bindings", "ratsarbeit@1", "relaxation_authorities"], [entry])

      assert {:error, reason} = LabelStore.import_registry(db, seed2)
      assert reason =~ "invalid_output_kind"
      assert reason =~ "unbekannte-ausgabe"
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

      seed2 = deep_put(seed, ["observer_types", "fraktionskollege"], "processing_domain")

      assert {:error, reason} = LabelStore.import_registry(db, seed2)
      assert reason =~ "Beobachtertyp unveränderlich"
      assert reason =~ "person != processing_domain"
    end

    # #598: Wer eine Lockerungsbefugnis haelt, muss eine Person sein; schon
    # die Engine-Projektion des Imports lehnt die Herabstufung ab.
    test "Inhaberin einer Lockerungsbefugnis kann keine Verarbeitungsdomäne sein (#598)", %{
      db: db,
      seed: seed
    } do
      seed2 = deep_put(seed, ["observer_types", "nutzende-person"], "processing_domain")

      assert {:error, reason} = LabelStore.import_registry(db, seed2)
      assert reason =~ "relaxation_authority_not_person"
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
