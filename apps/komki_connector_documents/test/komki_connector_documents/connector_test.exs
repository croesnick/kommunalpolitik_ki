defmodule KomkiConnectorDocuments.ConnectorTest do
  use ExUnit.Case, async: true

  alias KomkiConnectorDocuments.TestPDF
  alias Sidecar.{Client, Server}

  # Zufallssuffixe wie im komki-Testsupport (TestHelpers.tmp_base/1):
  # unique_integer wiederholt sich ueber VM-Neustarts, und Reste
  # abgestuerzter Laeufe liessen File.ln_s!/:listen sonst scheitern.
  setup do
    root = tmp("kcd")
    dir = Path.join(root, "documents")
    File.mkdir_p!(dir)
    File.write!(Path.join(dir, "doc-oeffentlich.md"), "# Oeffentliche Notiz\n")
    File.write!(Path.join(dir, "doc-doppelt.md"), "# Nur Markdown\n")
    TestPDF.multi_page(Path.join(dir, "doc-doppelt.pdf"))
    TestPDF.multi_page(Path.join(dir, "doc-drucksache.pdf"))
    TestPDF.no_text(Path.join(dir, "doc-scan.pdf"))
    TestPDF.invalid(Path.join(dir, "doc-broken.pdf"))
    File.write!(Path.join(root, "geheim.md"), "geheim\n")
    File.ln_s!(Path.join(root, "geheim.md"), Path.join(dir, "doc-link.md"))
    File.ln_s!(Path.join(root, "geheim.md"), Path.join(dir, "doc-link-pdf.pdf"))

    # Kurzer Socket-Pfad: macOS begrenzt Unix-Socket-Pfade auf 103 Byte.
    socket = tmp("kcd") <> ".sock"
    {:ok, state} = KomkiConnectorDocuments.init(dir)
    {:ok, listener} = Server.listen(socket)
    token = Sidecar.Token.provision!(socket)
    pid = spawn(fn -> Server.accept_loop(listener, KomkiConnectorDocuments, state, token) end)
    _ = :socket.setopt(listener, {:otp, :controlling_process}, pid)

    on_exit(fn ->
      Process.exit(pid, :kill)
      File.rm(socket)
      File.rm_rf!(root)
    end)

    %{socket: socket, dir: dir}
  end

  defp tmp(prefix) do
    suffix = Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
    Path.join(System.tmp_dir!(), prefix <> "-" <> suffix)
  end

  test "liest ein Raumdokument", %{socket: socket} do
    assert {:ok, %{"document_id" => "doc-oeffentlich", "content" => "# Oeffentliche Notiz\n"}} =
             Client.call(socket, "c1", "read", %{"document_id" => "doc-oeffentlich"})
  end

  # Ticket #290: PDF-Text je Seite mit Seitenanker, dazu die Highlights
  # mit Kommentar und markiertem Text (eine Zeile, einmal mehrzeilig).
  # Die versteckte dritte Markierung des Fixtures darf nicht erscheinen.
  test "liest ein mehrseitiges PDF mit Highlights", %{socket: socket} do
    assert {:ok, %{"document_id" => "doc-drucksache", "content" => content}} =
             Client.call(socket, "c1", "read", %{"document_id" => "doc-drucksache"})

    assert content =~
             "[Seite 1]\nErste Seite des Testdokuments mit Einleitungstext.\nWeitere Zeile auf der ersten Seite."

    assert content =~
             "[Seite 2]\nMarkierung\nNachfolgender Satz bleibt unmarkiert.\nDritte Zeile im Testdokument."

    assert content =~ "---\n\nHighlights:\n"
    assert content =~ "- Seite 2: „Markierung“ — Kommentar: Wichtige Stelle"

    assert content =~
             "- Seite 2: „Nachfolgender Satz bleibt unmarkiert. Dritte Zeile im Testdokument.“ — Kommentar: Mehrzeilige Markierung"

    refute content =~ "Versteckte Markierung"
  end

  # Ticket #290: Ohne Textebene gibt es einen klaren Fehler statt eines
  # leeren Texts.
  test "PDF ohne Textebene: klarer Fehler statt leerem Text", %{socket: socket} do
    assert {:error, %{"code" => "upstream-error"}} =
             Client.call(socket, "c1", "read", %{"document_id" => "doc-scan"})
  end

  test "Datei mit PDF-Endung und kaputten Bytes: upstream-error", %{socket: socket} do
    assert {:error, %{"code" => "upstream-error"}} =
             Client.call(socket, "c1", "read", %{"document_id" => "doc-broken"})
  end

  # pdfium reicht ein einzelnes \r ungefiltert durch; der Connector
  # normalisiert es zu \n, statt rohe Wagenruecklaeufe zuzulassen.
  test "einzelnes \\r im Text wird zu \\n normalisiert", %{socket: socket, dir: dir} do
    TestPDF.lone_cr(Path.join(dir, "doc-cr.pdf"))

    assert {:ok, %{"content" => content}} =
             Client.call(socket, "c1", "read", %{"document_id" => "doc-cr"})

    assert content =~ "Zeile mit Wagenruecklauf\nDritte Zeile"
    refute content =~ "\r"
  end

  test "extrahierter Text ueber 1 MiB: too-large", %{socket: socket, dir: dir} do
    # Das grosse Fixture baut nur dieser Test (~2,4 MB Schreibarbeit).
    TestPDF.big(Path.join(dir, "doc-riesig.pdf"))

    assert {:error, %{"code" => "too-large"}} =
             Client.call(socket, "c1", "read", %{"document_id" => "doc-riesig"})
  end

  # Die Dateigrenze greift vor dem Parsen: deutlich ueber 64 MiB, ohne
  # gueltige PDF-Bytes dahinter — der Connector liest nichts.
  test "PDF-Datei ueber 64 MiB: too-large ohne Parsen", %{socket: socket, dir: dir} do
    padding = 64 * 1024 * 1024

    File.write!(
      Path.join(dir, "doc-riesen-file.pdf"),
      "%PDF-1.4\n" <> String.duplicate("X", padding)
    )

    assert {:error, %{"code" => "too-large"}} =
             Client.call(socket, "c1", "read", %{"document_id" => "doc-riesen-file"})
  end

  test "Markdown gewinnt vor dem PDF bei gleichem Namen", %{socket: socket} do
    assert {:ok, %{"document_id" => "doc-doppelt", "content" => "# Nur Markdown\n"}} =
             Client.call(socket, "c1", "read", %{"document_id" => "doc-doppelt"})
  end

  test "fehlendes Dokument: not-found", %{socket: socket} do
    assert {:error, %{"code" => "not-found"}} =
             Client.call(socket, "c2", "read", %{"document_id" => "doc-phantom"})
  end

  test "Symlink wird nicht verfolgt: forbidden-path", %{socket: socket} do
    assert {:error, %{"code" => "forbidden-path"}} =
             Client.call(socket, "c3", "read", %{"document_id" => "doc-link"})

    assert {:error, %{"code" => "forbidden-path"}} =
             Client.call(socket, "c3", "read", %{"document_id" => "doc-link-pdf"})
  end

  test "Pfade scheitern am Manifest-Pattern", %{socket: socket} do
    for id <- ["../geheim", "/etc/passwd", "Doc", "doc.md"] do
      assert {:error, %{"code" => "bad-request"}} =
               Client.call(socket, "c4", "read", %{"document_id" => id})
    end
  end

  test "ping meldet die Fassung", %{socket: socket} do
    assert {:ok, %{"version" => "komki-documents/1", "ops" => ["read"]}} =
             Client.call(socket, "c5", "ping", %{})
  end
end
