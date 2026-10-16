defmodule KomkiMediator.JournalTest do
  use ExUnit.Case, async: false

  alias KomkiMediator.{Journal, TestHelpers}
  alias KomkiPolicy.JSON

  setup do
    # Ordnungsunabhaengig: ein frueherer Test (z. B. http_tests Supervisor-
    # Baum, der Exits trapt und Test-Raeumung ueberlebt) kann den benannten
    # Journal-Prozess hinterlassen haben. Erst stoppen, dann neu starten.
    KomkiMediator.TestHelpers.stop_named(KomkiMediator.Journal)

    base = KomkiMediator.TestHelpers.provisioned_base()
    path = Path.join([base, "mediator", "journal", "pdr.jsonl"])
    %{path: path}
  end

  test "append schreibt eine kanonische JSONL-Zeile", %{path: path} do
    {:ok, _} = Journal.start_link(path)

    record = %{
      "schema" => "komki-pdr/1",
      "decision_id" => "pdr-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      "tool" => "ping",
      "decision" => "permit",
      "outcome" => "admitted",
      "admitted" => true
    }

    assert :ok = Journal.append(KomkiMediator.Journal, record)

    # Orakel: der neu angehaengte Chunk ist exakt das kanonische Dokument
    # (byte-identisch), parsen und re-kanonisieren liefert dieselben Bytes.
    content = File.read!(path)
    assert content == JSON.canonical(record)
    {:ok, parsed} = JSON.parse(content)
    assert JSON.canonical(parsed) == content

    # Nur der Journal-Prozess wächst: zweiter Append haengt rein,alter
    # Inhalt bleibt.
    second = %{
      "schema" => "komki-pdr/1",
      "decision_id" => "pdr-bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
      "tool" => "ping"
    }

    assert :ok = Journal.append(KomkiMediator.Journal, second)
    second_chunk = List.last(TestHelpers.journal_chunks_raw(path))

    assert second_chunk == JSON.canonical(second)
    assert content <> second_chunk == File.read!(path)
  end

  test "fehlerhaftes Oeffnen beendet den Start (fail-closed)" do
    # ein Verzeichnis an der Dateiposition
    base = KomkiMediator.TestHelpers.tmp_base()
    blocked = Path.join([base, "mediator", "journal", "pdr.jsonl"])
    File.mkdir_p!(blocked)

    # Trap: der linked Exit beim init-{:stop, ...} wird als {:error, ...}
    # zurueckgemeldet, damit der Aufrufer den Grund haengt.
    Process.flag(:trap_exit, true)
    assert {:error, {:journal_open, :eisdir}} = Journal.start_link(blocked)
  end
end
