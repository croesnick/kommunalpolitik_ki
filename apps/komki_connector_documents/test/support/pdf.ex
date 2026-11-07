defmodule KomkiConnectorDocuments.TestPDF do
  @moduledoc """
  Builds the connector's test PDFs in the test itself (ticket #290), so no
  binary fixture lives in the repo. Five shapes:

    * `multi_page/1`: two pages of text; page 2 carries three highlight
      annotations with comments: one single-line, one multi-line, one
      hidden (/F 6), which must stay out of the agent context.
    * `no_text/1`: one page without a text layer (a filled rectangle, like
      a scan without OCR).
    * `lone_cr/1`: one page with a lone \\r in its text; pdfium passes raw
      control characters through, the connector normalizes them to \\n.
    * `big/1`: more than 1 MiB of extractable text, for the frame limit.
    * `invalid/1`: a file with a PDF extension but broken bytes.
    * `tight_lines/1`: five lines of 12 pt text at 14.4 pt line spacing with
      a single-line and a two-line highlight (ticket #368).

  The PDF syntax is handwritten and deliberately minimal: catalog, pages,
  one Helvetica Type1 font, one content stream per page with an absolute
  text matrix (`Tm`), plus `/Subtype /Highlight` annotations with `/Rect`
  and `/Contents`. The xref uses real offsets, so pdfium opens every file
  without repair.
  """

  @doc """
  Two pages. Page 1: two lines. Page 2: three lines; line 1 is highlighted
  on its own (comment „Wichtige Stelle“), lines 2 and 3 together (comment
  „Mehrzeilige Markierung“); the third annotation (comment „Versteckte
  Markierung“) is hidden (/F 6) and must not appear. Coordinates are PDF
  points, origin bottom left.
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
  One page without a text layer, just a filled rectangle (a scan without
  OCR). The connector must report an error, not empty text.
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

  @doc "One page with a lone \\r in its text (no \\r\\n pair)."
  @spec lone_cr(Path.t()) :: :ok
  def lone_cr(path) do
    stream =
      "BT\n/F1 12 Tf\n1 0 0 1 72 700 Tm\n(Zeile mit\\rWagenruecklauf) Tj\n1 0 0 1 72 650 Tm\n(Dritte Zeile) Tj\nET\n"

    objects = [
      "<< /Type /Catalog /Pages 2 0 R >>",
      "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
      page(parent: "2 0 R", contents: "4 0 R"),
      {:stream, stream},
      "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>"
    ]

    File.write!(path, assemble(objects))
  end

  @doc """
  One page, five lines in 12 pt Helvetica at 14.4 pt line spacing (baselines
  700, 685.6, 671.2, 656.8, 642.4). Highlight 1 covers line 3 only (comment
  „Einzeilig“), highlight 2 covers lines 4 and 5 (comment „Zweizeilig“).
  The rectangles span roughly the line pitch, as viewers draw them; the
  character boxes of the neighboring lines reach into them, but their
  baselines lie outside.
  """
  @spec tight_lines(Path.t()) :: :ok
  def tight_lines(path) do
    stream =
      text_stream([
        {{72, 700}, "Alpha eins"},
        {{72, 685.6}, "Beta zwei"},
        {{72, 671.2}, "Gamma drei"},
        {{72, 656.8}, "Delta vier"},
        {{72, 642.4}, "Epsilon fuenf"}
      ])

    objects = [
      "<< /Type /Catalog /Pages 2 0 R >>",
      "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
      page(parent: "2 0 R", contents: "4 0 R", annots: "[6 0 R 7 0 R]"),
      {:stream, stream},
      "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
      annot({70, 666.5, 200, 683}, "Einzeilig", 4),
      annot({70, 637, 200, 668}, "Zweizeilig", 4)
    ]

    File.write!(path, assemble(objects))
  end

  @doc "A file with a PDF extension and broken bytes."
  @spec invalid(Path.t()) :: :ok
  def invalid(path), do: File.write!(path, "kein PDF, nur Bytes mit Endung\n")

  @doc """
  One page with more than 1 MiB of extractable text, for the protocol's
  frame limit. pdfium truncates overlong lines, so the text comes from many
  short lines spread over distinct baselines that pdfium cannot merge.
  """
  @spec big(Path.t()) :: :ok
  def big(path) do
    lines =
      Enum.map(1..40_000//1, fn number ->
        # 3 000 baseline slots 0.2 pt apart: about 13 short lines each.
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

  defp text_stream(lines) do
    entries =
      Enum.map(lines, fn {{x, y}, text} ->
        "1 0 0 1 #{x} #{y} Tm\n(#{text}) Tj\n"
      end)

    "BT\n/F1 12 Tf\n" <> Enum.join(entries) <> "ET\n"
  end

  # opts: :parent, :contents, :annots (optional), :no_font (scan pages
  # need no font resource).
  defp page(opts) do
    parent = Keyword.fetch!(opts, :parent)
    contents = Keyword.fetch!(opts, :contents)
    annots = if a = opts[:annots], do: " /Annots #{a}", else: ""
    resources = if opts[:no_font], do: "<< >>", else: "<< /Font << /F1 5 0 R >> >>"

    "<< /Type /Page /Parent #{parent} /MediaBox [0 0 612 792] " <>
      "/Resources #{resources} /Contents #{contents}#{annots} >>"
  end

  # /F: 4 = print (visible), 6 = hidden + print. /C [1 1 0] = yellow.
  defp annot({left, bottom, right, top}, contents, flags) do
    "<< /Type /Annot /Subtype /Highlight /Rect [#{left} #{bottom} #{right} #{top}] " <>
      "/Contents (#{contents}) /C [1 1 0] /F #{flags} >>"
  end

  defp assemble(objects) do
    header = "%PDF-1.4\n"

    {chunks, offsets} =
      objects
      |> Enum.with_index(1)
      |> Enum.map_reduce(byte_size(header), fn {content, number}, offset ->
        chunk = object_chunk(number, content)
        {{chunk, offset}, offset + byte_size(chunk)}
      end)
      |> then(fn {pairs, _end} -> Enum.unzip(pairs) end)

    body = Enum.join(chunks)
    count = length(objects)

    xref_entries =
      Enum.map(offsets, fn offset ->
        String.pad_leading(Integer.to_string(offset), 10, "0") <> " 00000 n \n"
      end)

    header <>
      body <>
      "xref\n0 #{count + 1}\n0000000000 65535 f \n" <>
      Enum.join(xref_entries) <>
      "trailer\n<< /Size #{count + 1} /Root 1 0 R >>\nstartxref\n#{byte_size(header) + byte_size(body)}\n%%EOF\n"
  end

  defp object_chunk(number, {:stream, data}) do
    "#{number} 0 obj\n<< /Length #{byte_size(data)} >>\nstream\n#{data}endstream\nendobj\n"
  end

  defp object_chunk(number, content) do
    "#{number} 0 obj\n#{content}\nendobj\n"
  end
end
