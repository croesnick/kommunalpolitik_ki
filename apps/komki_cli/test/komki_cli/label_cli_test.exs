defmodule KomkiCli.LabelCLITest do
  # KOMKI_HOME bleibt unberuehrt: alle label-Befehle laufen mit explizitem
  # --db auf temporaere Bereiche (TestSupport.tmp_area!).
  use ExUnit.Case, async: true

  alias KomkiCli.{CLI, TestSupport}
  alias KomkiPolicy.{Derive, Registry}

  @seed_path Path.join([:code.priv_dir(:komki_cli), "fixtures", "registry-seed.json"])

  @probe_content_ref "/tmp/komki-fixture/brief-4711.docx"

  setup do
    db = Path.join(TestSupport.tmp_area!("komki-label-cli"), "registry.db")
    {:ok, db: db}
  end

  # ========================================================================
  # CLI-Oberflaeche
  # ========================================================================

  describe "CLI-Oberflaeche (`komki label …`)" do
    test "leiser Store rendert leere Abschnitte (Exit 0)", %{db: db} do
      {out, 0} = CLI.run(["label", "list", "--db", db])
      assert out =~ "Bindungen: (keine)"
      assert out =~ "Objekte: (keine)"
    end

    test "classify ohne --decided-by ist ein Optimus-Usage-Fehler (Exit 2)", %{db: db} do
      {out, 2} = CLI.run(["label", "classify", "brief-4711@v1", "--db", db])
      assert out =~ "missing required options: --decided-by"
    end

    test "komki label --help druckt den usage-Block (Exit 0)" do
      {out, 0} = CLI.run(["label", "--help"])
      assert out =~ "USAGE:"
      assert out =~ "classify"
      assert out =~ "export"
    end

    test "Fehler rendern als Fehlerzeile mit Exit 2 (unbekanntes Objekt beim classify)", %{
      db: db
    } do
      {out, 2} =
        CLI.run([
          "label",
          "classify",
          "unbekannt-brief@v1",
          "--label",
          "ratsarbeit@1",
          "--decided-by",
          "nutzende-person",
          "--basis",
          "Basisangabe",
          "--db",
          db
        ])

      assert out =~ "unbekanntes Objekt"
    end

    test "Registry-Datei nicht lesbar -> Fehlerzeile, Exit 2", %{db: db} do
      missing = Path.join(Path.dirname(db), "gibts-nicht.json")
      {out, 2} = CLI.run(["label", "import", missing, "--db", db])
      assert out =~ "nicht lesbar"
    end

    test "quarantine mit falscher Objektreferenz (ohne @VER) -> Fehler, Exit 2", %{db: db} do
      {out, 2} =
        CLI.run([
          "label",
          "quarantine",
          "ohne-version",
          "--content-ref",
          @probe_content_ref,
          "--origin",
          "synthetisch",
          "--decided-by",
          "nutzende-person",
          "--basis",
          "Basisangabe",
          "--db",
          db
        ])

      assert out =~ "ungueltige Version" or out =~ "OBJ@VER"
    end
  end

  # ========================================================================
  # End-to-End-Akzeptanz (Ticket-#91-Kern): CLI-Runde -> Γ-Export ->
  # Engine-Kompilierung -> KomkiPolicy.Derive.decide
  # ========================================================================

  describe "End-to-End in den Policy-Kern (R.2.5/R.5.4, CONTRACT § 2.2/§ 2.3)" do
    test "import -> quarantine -> classify -> export -> decide ergibt permit", %{db: db} do
      {_, 0} = CLI.run(["label", "import", @seed_path, "--db", db])

      {_, 0} =
        CLI.run([
          "label",
          "quarantine",
          "brief-4711@v1",
          "--content-ref",
          @probe_content_ref,
          "--origin",
          "synthetische RIS-Probe",
          "--decided-by",
          "nutzende-person",
          "--basis",
          "Eingang: Unterlage 4711 (Quelle: synthetische Probe, Ticket #91)",
          "--db",
          db
        ])

      {_, 0} =
        CLI.run([
          "label",
          "classify",
          "brief-4711@v1",
          "--label",
          "ratsarbeit@1",
          "--decided-by",
          "nutzende-person",
          "--basis",
          "Einordnung: nichtoeffentliche Ratsarbeit (Quelle: synthetische Probe)",
          "--db",
          db
        ])

      export_path = Path.join(Path.dirname(db), "gamma-export.json")
      {_, 0} = CLI.run(["label", "export", "--out", export_path, "--db", db])

      assert {:ok, _compiled} =
               export_path |> File.read!() |> JSON.decode!() |> Registry.compile()

      {:ok, compiled} = export_path |> File.read!() |> JSON.decode!() |> Registry.compile()

      intent = %{
        "schema" => "komki-intent/1",
        "intent_id" => "probe-intent",
        "operation" => "admit",
        "object" => "brief-4711@v1",
        "workspace" => "sitzungsraum"
      }

      snapshot =
        snapshot("probe-snapshot", %{
          "object_id" => "brief-4711",
          "version" => "v1",
          "classification" => "classified",
          "labels" => ["ratsarbeit@1"]
        })

      assert {:ok, decision} = Derive.decide(compiled, snapshot, intent)
      assert decision["decision"] == "permit"
      assert decision["checked_label"] == ["ratsarbeit@1"]
    end

    test "Gegenprobe: Quarantäne-Objekt ist deny mit blocker object_quarantine (R.2.5)", %{
      db: db
    } do
      {_, 0} = CLI.run(["label", "import", @seed_path, "--db", db])

      {_, 0} =
        CLI.run([
          "label",
          "quarantine",
          "protokoll-9@v1",
          "--content-ref",
          @probe_content_ref,
          "--origin",
          "synthetische RIS-Probe",
          "--decided-by",
          "nutzende-person",
          "--basis",
          "Eingang ohne Eingordnung (Quelle: synthetische Probe)",
          "--db",
          db
        ])

      {:ok, compiled} = export_registry_json(db)

      intent = %{
        "schema" => "komki-intent/1",
        "intent_id" => "quarantine-intent",
        "operation" => "admit",
        "object" => "protokoll-9@v1",
        "workspace" => "sitzungsraum"
      }

      snapshot =
        snapshot("quarantine-snapshot", %{
          "object_id" => "protokoll-9",
          "version" => "v1",
          "classification" => "quarantine",
          "labels" => []
        })

      assert {:ok, decision} = Derive.decide(compiled, snapshot, intent)
      assert decision["decision"] == "deny"
      assert Enum.any?(decision["blockers"], &(&1["code"] == "object_quarantine"))
    end
  end

  # ========================================================================
  # Helfer
  # ========================================================================

  # Snapshot-Orakel (komki-snapshot/1): beide End-to-End-Tests teilen sich
  # dieselbe Form und unterscheiden sich nur in snapshot_id und Objektstand
  # (die beiden Argumente).
  defp snapshot(snapshot_id, object) do
    %{
      "schema" => "komki-snapshot/1",
      "snapshot_id" => snapshot_id,
      "registry_ref" => "komki-synth-demo",
      "identity" => "nutzende-person",
      "workspace" => %{
        "workspace_id" => "sitzungsraum",
        "bindings" => ["ratsarbeit@1"],
        "valid" => true,
        "environment" => "lokal@1"
      },
      "object" => object,
      "facts" => %{
        "purpose" => %{
          "value" => "sitzungsvorbereitung",
          "source" => "test",
          "source_kind" => "test"
        },
        "workspace_scope_ok" => %{"value" => true, "source" => "test", "source_kind" => "test"},
        "has_operation_right" => %{"value" => true, "source" => "test", "source_kind" => "test"},
        "has_object_access_right" => %{
          "value" => true,
          "source" => "test",
          "source_kind" => "test"
        },
        "audit_path_ready" => %{"value" => true, "source" => "test", "source_kind" => "test"},
        "environment_observers_complete" => %{
          "value" => true,
          "source" => "test",
          "source_kind" => "test"
        }
      }
    }
  end

  defp export_registry_json(db) do
    with {:ok, json} <- KomkiCli.LabelStore.export(db) do
      Registry.compile(JSON.decode!(json))
    end
  end
end
