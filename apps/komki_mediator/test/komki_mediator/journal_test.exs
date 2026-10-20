defmodule KomkiMediator.JournalTest do
  use ExUnit.Case, async: false

  alias KomkiMediator.Journal
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

  test "append schreibt kanonische, verkettete Datensaetze", %{path: path} do
    {:ok, _} = Journal.start_link(path)

    first = %{"schema" => "komki-pdr/2", "decision_id" => "pdr-a", "tool" => "ping"}
    assert :ok = Journal.append(KomkiMediator.Journal, first)

    # Orakel: der Chunk ist exakt das kanonische Dokument samt Kettenfeldern
    # (byte-identisch), der erste Datensatz haengt am Genesis-Anker.
    content = File.read!(path)

    assert content ==
             JSON.canonical(Map.merge(first, %{"seq" => 0, "prev_hash" => Journal.genesis()}))

    second = %{"schema" => "komki-pdr/2", "decision_id" => "pdr-b", "tool" => "ping"}
    assert :ok = Journal.append(KomkiMediator.Journal, second)
    [chunk1, chunk2] = Journal.split_records(File.read!(path))

    assert chunk1 == content
    {:ok, rec2} = JSON.parse(chunk2)
    assert rec2["seq"] == 1
    assert rec2["prev_hash"] == KomkiMediator.Hash.sha256_hex(chunk1)

    assert {:ok, %{records: 2, chained: 2, legacy: 0, head_hash: head}} =
             Journal.verify(File.read!(path))

    assert head == KomkiMediator.Hash.sha256_hex(chunk2)
  end

  test "Kette setzt sich ueber einen Neustart des Writers fort", %{path: path} do
    {:ok, pid} = Journal.start_link(path)
    :ok = Journal.append(KomkiMediator.Journal, %{"n" => 1})
    GenServer.stop(pid)

    {:ok, _} = Journal.start_link(path)
    :ok = Journal.append(KomkiMediator.Journal, %{"n" => 2})

    assert {:ok, %{records: 2, chained: 2}} = Journal.verify(File.read!(path))
  end

  test "alte Datensaetze ohne Kettenfelder sind als Praefix zulaessig", %{path: path} do
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, JSON.canonical(%{"schema" => "komki-pdr/1", "n" => 0}))

    {:ok, _} = Journal.start_link(path)
    :ok = Journal.append(KomkiMediator.Journal, %{"n" => 1})

    assert {:ok, %{records: 2, chained: 1, legacy: 1}} = Journal.verify(File.read!(path))
  end

  describe "verify/1 erkennt Manipulation" do
    setup %{path: path} do
      {:ok, _} = Journal.start_link(path)

      for n <- 0..2 do
        :ok = Journal.append(KomkiMediator.Journal, %{"decision" => "deny", "n" => n})
      end

      %{records: Journal.split_records(File.read!(path))}
    end

    test "geaenderter Datensatz (kanonisch neu geschrieben)", %{records: [a, b, c]} do
      {:ok, rec} = JSON.parse(b)
      forged = JSON.canonical(%{rec | "decision" => "permit"})

      assert {:error, %{index: 2, reason: reason}} = Journal.verify(a <> forged <> c)
      assert reason =~ "prev_hash"
    end

    test "entfernter Datensatz", %{records: [a, _b, c]} do
      assert {:error, %{index: 1}} = Journal.verify(a <> c)
    end

    test "vertauschte Datensaetze", %{records: [a, b, c]} do
      assert {:error, %{index: 1}} = Journal.verify(a <> c <> b)
    end

    test "eingeschobener Datensatz ohne Kettenfelder", %{records: [a, b, c]} do
      legacy = JSON.canonical(%{"decision" => "permit"})
      assert {:error, %{index: 1, reason: reason}} = Journal.verify(a <> legacy <> b <> c)
      assert reason =~ "ohne Kettenfelder"
    end

    test "abgeschnittener letzter Datensatz", %{records: [a, b, c]} do
      truncated = binary_part(c, 0, byte_size(c) - 3)
      assert {:error, %{index: 2}} = Journal.verify(a <> b <> truncated)
    end

    test "nicht kanonische Bytes", %{records: [a, b, c]} do
      assert {:error, %{index: 1, reason: "nicht kanonisch"}} =
               Journal.verify(a <> String.replace(b, "  ", "   ", global: false) <> c)
    end

    test "geaenderter letzter Datensatz bleibt gueltig, nur der Kopf-Hash aendert sich (Grenze)",
         %{records: [a, b, c]} do
      {:ok, %{head_hash: original}} = Journal.verify(a <> b <> c)
      {:ok, rec} = JSON.parse(c)
      forged = JSON.canonical(%{rec | "decision" => "permit"})

      assert {:ok, %{head_hash: head}} = Journal.verify(a <> b <> forged)
      refute head == original
    end

    test "Kuerzung am Ende bleibt eine gueltige Kette (Grenze: braucht Kontrollpunkte)",
         %{records: [a, b, _c]} do
      assert {:ok, %{records: 2}} = Journal.verify(a <> b)
    end
  end

  test "gebrochene Datei verhindert den Start (fail-closed)", %{path: path} do
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, "{\n  \"n\": 1")

    Process.flag(:trap_exit, true)
    assert {:error, {:journal_corrupt, %{index: 0}}} = Journal.start_link(path)
  end

  test "append_only setzt uappnd: Anhaengen geht, Ueberschreiben nicht", %{path: path} do
    {:ok, _} = Journal.start_link({path, append_only: true})
    on_exit(fn -> System.cmd("/usr/bin/chflags", ["nouappnd", path]) end)

    :ok = Journal.append(KomkiMediator.Journal, %{"n" => 0})
    {flags, 0} = System.cmd("/usr/bin/stat", ["-f", "%Sf", path])
    assert flags =~ "uappnd"

    assert {:error, :eperm} = File.write(path, "")
    assert {:error, :eperm} = File.rm(path)
    assert {:ok, %{records: 1}} = Journal.verify(File.read!(path))
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
