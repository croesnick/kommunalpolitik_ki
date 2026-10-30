defmodule KomkiConnectorDocuments.TestPDF do
  @moduledoc """
  Baut die Test-PDFs des Connectors selbst (Ticket #290): kein Binär-Fixture
  im Repo — die Bytes entstehen im Test. Fünf Formen:

    * `multi_page/1` — zwei Seiten mit Text; auf Seite 2 drei
      Highlight-Annotationen mit Kommentar: eine einzeilig, eine
      mehrzeilig, eine versteckt (/F 6) — versteckte Markierungen
      gehoeren nicht in den Agentenkontext.
    * `no_text/1` — eine Seite ohne Textebene (gefülltes Rechteck statt
      Text, wie ein Scan ohne OCR).
    * `lone_cr/1` — eine Seite mit einzelnem \\r im Text: pdfium reicht
      rohe Steuerzeichen durch, der Connector normalisiert zu \\n.
    * `big/1` — extrahierbarer Text über 1 MiB, für die Frame-Grenze.
    * `invalid/1` — eine Datei mit PDF-Endung, aber kaputten Bytes.

  Die PDF-Syntax ist handgeschrieben und absichtlich minimal: Catalog,
  Pages, eine Helvetica-Type1-Font, je Seite ein Content-Stream mit
  absoluter Textmatrix (`Tm`), dazu die Annotationen mit /Subtype
  /Highlight, /Rect und /Contents. Die xref wird mit echten Offsets
  berechnet, damit jedes PDF ohne Reparatur lesbar ist.
  """

  @doc """
  Zweiseitiges PDF. Seite 1: zwei Zeilen. Seite 2: drei Zeilen mit
  Highlights — Zeile 1 ganz markiert (Kommentar „Wichtige Stelle“), die
  Zeilen 2 und 3 zusammen markiert (Kommentar „Mehrzeilige Markierung“);
  die dritte Annotation (Kommentar „Versteckte Markierung“) trägt das
  Hidden-Flag (/F 6) und darf nicht erscheinen. Alle Koordinaten sind
  PDF-Punkte, Ursprung unten links.
  """
  @spec multi_page(Path.t()) :: :ok
  def multi_page(path) do
    page1 =
      text_stream([
        {{72, 720}, "Erste Seite des Testdokuments mit Einleitungstext."},
        {{72, 670}, "Weitere Zeile auf der ersten Seite."}
      ])

    page2 =
      text_stream([
        {{72, 700}, "Markierung"},
        {{72, 650}, "Nachfolgender Satz bleibt unmarkiert."},
        {{72, 600}, "Dritte Zeile im Testdokument."}
      ])

    objects = [
      "<< /Type /Catalog /Pages 2 0 R >>",
      "<< /Type /Pages /Kids [3 0 R 6 0 R] /Count 2 >>",
      page(parent: "2 0 R", contents: "4 0 R"),
      {:stream, page1},
      "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
      page(parent: "2 0 R", contents: "7 0 R", annots: "[8 0 R 9 0 R 10 0 R]"),
      {:stream, page2},
      annot({60, 688, 200, 714}, "Wichtige Stelle", 4),
      annot({60, 592, 400, 666}, "Mehrzeilige Markierung", 4),
      annot({60, 542, 300, 570}, "Versteckte Markierung", 6)
    ]

    File.write!(path, assemble(objects))
  end

  @doc """
  Einseitiges PDF ohne Textebene: nur ein gefülltes Rechteck (Scan ohne
  OCR). Der Connector muss das als klaren Fehler melden, nicht als leeren
  Text.
  """
  @spec no_text(Path.t()) :: :ok
  def no_text(path) do
    scanned = "0 0 1 rg 100 100 400 500 re f\n"

    objects = [
      "<< /Type /Catalog /Pages 2 0 R >>",
      "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
      page(parent: "2 0 R", contents: "4 0 R", no_font: true),
      {:stream, scanned}
    ]

    File.write!(path, assemble(objects))
  end

  @doc "Eine Seite mit einzelnem \\r im Text (kein \\r\\n-Paar)."
  @spec lone_cr(Path.t()) :: :ok
  def lone_cr(path) do
    stream =
      "BT\n/F1 12 Tf\n1 0 0 1 72 700 Tm\n(Zeile mit Wagenruecklauf) Tj\n1 0 0 1 72 650 Tm\n(Dritte Zeile) Tj\nET\n"

    objects = [
      "<< /Type /Catalog /Pages 2 0 R >>",
      "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
      page(parent: "2 0 R", contents: "4 0 R"),
      {:stream, stream},
      "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>"
    ]

    File.write!(path, assemble(objects))
  end

  @doc "Datei mit PDF-Endung und kaputten Bytes."
  @spec invalid(Path.t()) :: :ok
  def invalid(path), do: File.write!(path, "kein PDF, nur Bytes mit Endung\n")

  @doc """
  Einseitiges PDF mit ueber 1 MiB extrahierbarem Text — fuer die
  Frame-Grenze des Protokolls. pdfium kuerzt einzelne ueberlange Zeilen,
  der Text kommt deshalb aus vielen kurzen Zeilen; jede liegt auf
  eigener Baseline, damit pdfium sie nicht zu einer ueberlangen Zeile
  verschmilzt.
  """
  @spec big(Path.t()) :: :ok
  def big(path) do
    lines =
      Enum.map(1..40_000//1, fn number ->
        # 3 000 verteilte Baseline-Slots (0,2 Pt Abstand): gut 13 kurze
        # Zeilen je Slot, nirgends eine verschmelzbare Riesenzeile.
        y = 700 - rem(number, 3000) * 0.2
        "1 0 0 1 72 #{y} Tm\n(Zeile #{number} des grossen Testdokuments.) Tj\n"
      end)

    stream = "BT\n/F1 12 Tf\n" <> Enum.join(lines) <> "ET\n"

    objects = [
      "<< /Type /Catalog /Pages 2 0 R >>",
      "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
      page(parent: "2 0 R", contents: "4 0 R"),
      {:stream, stream},
      "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>"
    ]

    File.write!(path, assemble(objects))
  end

  # ------------------------------------------------------------------
  # PDF-Syntax
  # ------------------------------------------------------------------

  defp text_stream(lines) do
    entries =
      Enum.map(lines, fn {{x, y}, text} ->
        "1 0 0 1 #{x} #{y} Tm\n(#{text}) Tj\n"
      end)

    "BT\n/F1 12 Tf\n" <> Enum.join(entries) <> "ET\n"
  end

  # opts: :parent, :contents, :annots (optional), :no_font (Scan-Seiten
  # ohne Text brauchen die Font-Resource nicht).
  defp page(opts) do
    parent = Keyword.fetch!(opts, :parent)
    contents = Keyword.fetch!(opts, :contents)
    annots = if a = opts[:annots], do: " /Annots #{a}", else: ""
    resources = if opts[:no_font], do: "<< >>", else: "<< /Font << /F1 5 0 R >> >>"

    "<< /Type /Page /Parent #{parent} /MediaBox [0 0 612 792] " <>
      "/Resources #{resources} /Contents #{contents}#{annots} >>"
  end

  # /F: 4 = Print-Flag (sichtbar), 6 = Hidden+Print — versteckte
  # Markierungen bleiben dem Viewer verborgen und dem Connector auch.
  # /C [1 1 0] = typische Highlight-Farbe gelb.
  defp annot({left, bottom, right, top}, contents, flags) do
    "<< /Type /Annot /Subtype /Highlight /Rect [#{left} #{bottom} #{right} #{top}] " <>
      "/Contents (#{contents}) /C [1 1 0] /F #{flags} >>"
  end

  defp assemble(objects) do
    header = "%PDF-1.4\n"

    {body, offsets} =
      objects
      |> Enum.with_index(1)
      |> Enum.reduce({[], []}, fn {content, number}, {chunks, offsets} ->
        offset = chunks |> iodata_size() |> Kernel.+(byte_size(header))
        chunk = object_chunk(number, content)
        {[chunks, chunk], [{number, offset} | offsets]}
      end)

    body = :erlang.iolist_to_binary(body)
    xref_offset = byte_size(body) + byte_size(header)
    count = length(objects)

    xref_entries =
      for number <- 1..count//1 do
        offset = offsets |> List.keyfind(number, 0) |> elem(1)
        String.pad_leading(Integer.to_string(offset), 10, "0") <> " 00000 n \n"
      end

    header <>
      body <>
      "xref\n0 #{count + 1}\n0000000000 65535 f \n" <>
      Enum.join(xref_entries) <>
      "trailer\n<< /Size #{count + 1} /Root 1 0 R >>\nstartxref\n#{xref_offset}\n%%EOF\n"
  end

  defp object_chunk(number, {:stream, data}) do
    "#{number} 0 obj\n<< /Length #{byte_size(data)} >>\nstream\n#{data}endstream\nendobj\n"
  end

  defp object_chunk(number, content) do
    "#{number} 0 obj\n#{content}\nendobj\n"
  end

  defp iodata_size(chunks), do: :erlang.iolist_size(chunks)
end
