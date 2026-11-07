defmodule KomkiConnectorDocuments.Pdf do
  @moduledoc """
  Renders a PDF as text for `admit_document` (ticket #290): each page as a
  page anchor `[Seite N]` followed by its text, then the highlights of the
  user, each with its comment and the marked text.

  ## License and origin of the NIF

  Built on `ex_pdfium` 0.6.0 (MIT), a NIF over the Rust crate
  `pdfium-render` that binds Chromium's pdfium (BSD-3-Clause, Google).
  `rustler_precompiled` fetches the precompiled NIF from the GitHub
  releases of the ex_pdfium project (one artifact per platform, NIF ABI
  2.15 for OTP 27/28/29+, verified against the release checksums of the
  package); the bundled `libpdfium` comes from bblanchon/pdfium-binaries.
  No Rust toolchain, no pdfium build, no OCR (whether OCR is needed is
  ticket #289).

  ## Limits

  A PDF without a text layer (e.g. a scan) is an error (`upstream-error`),
  not empty text. The marked text of a highlight is made of the
  characters whose box overlaps the annotation rectangle horizontally and
  whose baseline (box center if the character has none) lies inside it
  (#368): the loose character boxes of ex_pdfium are taller than the line
  spacing, so a plain box overlap would take in neighboring lines. A
  rectangle that contains no baseline yields no marked text
  (`(keinen markierten Text erkannt)`). ex_pdfium does not expose
  QuadPoints (probe #278), so multi-line highlights are approximate, read
  top to bottom with lines joined by a space. Only visible
  `/Subtype /Highlight` annotations count; hidden ones (/F hidden flag),
  underlines and notes are ignored.

  The NIF's page index is 16 bit, so documents with 65 535 pages or more
  cannot be counted reliably and are rejected.
  """

  # Larger extracted text would not fit into a protocol frame anyway; page
  # extraction stops as soon as the page texts alone exceed it.
  @max_bytes Sidecar.Frame.max_bytes()

  # pdfium synthesizes spaces without a box: a gap of this share of the
  # font size counts as a word boundary.
  @word_gap_factor 0.2

  # From here on the NIF's page_count wraps modulo 65 536.
  @page_limit 65_535

  @doc """
  Renders the PDF at `path` as text with page anchors and highlights.
  Errors carry a code from the closed set of the frame protocol; the German
  `detail` only goes to the connector log (CONTRACT.md §3).
  """
  @spec render(Path.t()) :: {:ok, String.t()} | {:error, String.t(), String.t()}
  def render(path) do
    with {:ok, doc} <- open(path) do
      try do
        content(doc)
      after
        # ex_pdfium asks callers not to rely on GC to free documents.
        _ = ExPdfium.close(doc)
      end
    end
  rescue
    # E.g. in an escript, where the NIF cannot be dlopen'ed from the
    # archive (#288). The detail only reaches the local connector log.
    exception ->
      {:error, "internal",
       "PDF-Lesung fehlgeschlagen: #{inspect(exception.__struct__)} #{Exception.message(exception)}"}
  end

  defp open(path) do
    case ExPdfium.open(path) do
      {:ok, doc} ->
        {:ok, doc}

      {:error, :invalid_pdf} ->
        {:error, "upstream-error", "Datei ist kein lesbares PDF"}

      {:error, :password_error} ->
        {:error, "upstream-error", "PDF ist passwortgeschuetzt"}

      {:error, :unsupported_security} ->
        {:error, "upstream-error", "PDF-Verschluesselung nicht unterstuetzt"}

      {:error, :enoent} ->
        {:error, "not-found", "Dokument nicht gefunden"}

      {:error, reason} ->
        {:error, "internal", "PDF-Oeffnung fehlgeschlagen: #{inspect(reason)}"}
    end
  end

  defp content(doc) do
    with {:ok, count} <- page_count(doc),
         {:ok, pages} <- read_pages(doc, count),
         :ok <- require_text(pages),
         {:ok, highlights} <- read_highlights(doc, count) do
      content = assemble(pages, highlights)
      if byte_size(content) > @max_bytes, do: too_large(), else: {:ok, content}
    end
  end

  defp too_large, do: {:error, "too-large", "extrahierter Text groesser als 1 MiB"}

  defp page_count(doc) do
    case ExPdfium.page_count(doc) do
      {:ok, 0} ->
        {:error, "upstream-error", "PDF ohne Seiten"}

      {:ok, count} when count >= @page_limit ->
        {:error, "too-large", "PDF mit #{count} oder mehr Seiten (Lesegrenze 65 535)"}

      {:ok, count} ->
        {:ok, count}

      {:error, reason} ->
        {:error, "internal", "Seitenzahl nicht lesbar: #{inspect(reason)}"}
    end
  end

  # [{page number, text}]; empty pages keep their anchor. Line breaks are
  # normalized to \n (pdfium emits \r\n and occasionally a lone \r).
  defp read_pages(doc, count) do
    0..(count - 1)//1
    |> Enum.reduce_while({[], 0}, &add_page(doc, &1, &2))
    |> case do
      {pages, _bytes} -> {:ok, Enum.reverse(pages)}
      error -> error
    end
  end

  # Stops early once the page texts alone exceed the frame limit.
  defp add_page(doc, index, {pages, bytes}) do
    case ExPdfium.extract_text(doc, index) do
      {:ok, text} ->
        text = text |> String.replace(["\r\n", "\r"], "\n") |> String.trim()
        bytes = bytes + byte_size(text)

        if bytes > @max_bytes,
          do: {:halt, too_large()},
          else: {:cont, {[{index + 1, text} | pages], bytes}}

      {:error, reason} ->
        {:halt, {:error, "internal", "Seite nicht lesbar: #{inspect(reason)}"}}
    end
  end

  # No text at all means a scan without a text layer (no OCR until #289).
  defp require_text(pages) do
    if Enum.any?(pages, fn {_page, text} -> text != "" end),
      do: :ok,
      else: {:error, "upstream-error", "PDF ohne Textebene (Scan ohne OCR, Ticket #289)"}
  end

  # Read errors are fatal: a silently dropped highlight would look like a
  # page without highlights.
  defp read_highlights(doc, count) do
    0..(count - 1)//1
    |> Enum.reduce_while([], fn index, acc ->
      case page_highlights(doc, index) do
        {:ok, highlights} ->
          {:cont, [highlights | acc]}

        {:error, reason} ->
          {:halt, {:error, "internal", "Highlights nicht lesbar: #{inspect(reason)}"}}
      end
    end)
    |> case do
      {:error, _code, _detail} = error -> error
      per_page -> {:ok, per_page |> Enum.reverse() |> Enum.concat()}
    end
  end

  # Highlights the user hid in the viewer stay out of the agent context.
  # Characters are only read for pages that carry a visible highlight.
  defp page_highlights(doc, index) do
    with {:ok, annotations} <- ExPdfium.annotations(doc, index) do
      annotations
      |> Enum.filter(&(&1.type == :highlight and not &1.hidden))
      |> with_marked_text(doc, index)
    end
  end

  defp with_marked_text([], _doc, _index), do: {:ok, []}

  defp with_marked_text(visible, doc, index) do
    with {:ok, chars} <- ExPdfium.chars(doc, index) do
      {:ok,
       visible
       |> Enum.sort_by(&rect_position(&1.bounds))
       |> Enum.map(&highlight(index + 1, &1, chars))}
    end
  end

  # Top to bottom (PDF y grows upwards), then left to right.
  defp rect_position(nil), do: {0, 0}
  defp rect_position(rect), do: {-rect.top, rect.left}

  defp highlight(page, annotation, chars) do
    %{
      page: page,
      text: marked_text(chars, annotation.bounds),
      comment: clean(annotation.contents)
    }
  end

  defp marked_text(_chars, nil), do: ""

  defp marked_text(chars, rect) do
    chars
    # pdfium reports line breaks as characters; join_chars re-inserts gaps.
    |> Enum.reject(&(&1.char =~ ~r/\s/))
    |> Enum.filter(&(&1.bounds && marked?(&1, rect)))
    |> Enum.sort_by(fn char ->
      %{x: x, y: y} = pen_position(char)
      {-y, x}
    end)
    |> join_chars()
  end

  # Horizontally the box must overlap the rectangle, vertically the
  # baseline must lie inside it: the loose character boxes of ex_pdfium
  # are taller than the line spacing and would pull in neighboring lines
  # (ticket #368).
  defp marked?(%{bounds: box} = char, rect) do
    %{y: y} = pen_position(char)

    box.left < rect.right and box.right > rect.left and
      y >= rect.bottom and y <= rect.top
  end

  # The baseline origin is the stable anchor; synthesized characters may
  # lack it, then the box center stands in.
  defp pen_position(%{origin: %{x: x, y: y}}), do: %{x: x, y: y}

  defp pen_position(%{bounds: %{left: left, right: right, bottom: bottom, top: top}}),
    do: %{x: (left + right) / 2, y: (bottom + top) / 2}

  defp join_chars([]), do: ""

  defp join_chars([first | _rest] = chars) do
    rest =
      chars
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.map(fn [previous, char] -> [separator(previous, char), char.char] end)

    IO.iodata_to_binary([first.char | rest])
  end

  # A space at word gaps and line changes, nothing inside a word.
  defp separator(previous, char) do
    if same_line?(previous, char) and not word_gap?(previous, char), do: "", else: " "
  end

  defp same_line?(previous, char), do: abs(pen_position(char).y - pen_position(previous).y) < 1

  defp word_gap?(previous, char) do
    char.bounds.left - previous.bounds.right > previous.font_size * @word_gap_factor
  end

  defp assemble(pages, highlights) do
    text = Enum.map_join(pages, "\n\n", fn {page, text} -> "[Seite #{page}]\n" <> text end)

    case highlights do
      [] ->
        text

      _ ->
        text <> "\n\n---\n\nHighlights:\n\n" <> Enum.map_join(highlights, "\n", &highlight_line/1)
    end
  end

  defp highlight_line(highlight) do
    "- Seite #{highlight.page}: " <>
      marked_part(highlight.text) <> comment_part(highlight.comment)
  end

  defp marked_part(""), do: "(keinen markierten Text erkannt)"
  defp marked_part(text), do: "„#{text}“"

  defp comment_part(""), do: ""
  defp comment_part(comment), do: " — Kommentar: " <> comment

  # Comments may span lines; one line per highlight collapses whitespace.
  defp clean(nil), do: ""
  defp clean(text), do: text |> String.split() |> Enum.join(" ")
end
