defmodule KomkiConnectorDocuments.Pdf do
  @moduledoc """
  Liest ein PDF als Text fuer `admit_document` (Ticket #290): je Seite ein
  Seitenanker `[Seite N]` mit dem Seitentext, danach die Highlights der
  nutzenden Person, je mit Kommentar und markiertem Text.

  ## Lizenz und Herkunft des NIF

  Grundlage ist `ex_pdfium` 0.6.0 (MIT): ein NIF ueber die Rust-Kiste
  `pdfium-render`, der das pdfium des Chromium-Projekts (BSD-3-Clause,
  Google) anbindet. Der vorkompilierte NIF kommt per `rustler_precompiled`
  aus den GitHub-Releases des ex_pdfium-Projekts (je Plattform genau ein
  Artefakt, NIF-ABI 2.15 fuer OTP 27/28/29+, gegen die Release-Checksummen
  der Paketquelle verifiziert); das gebuendelte `libpdfium` baut das
  Projekt aus bblanchon/pdfium-binaries ein. Keine Rust-Toolchain, kein
  pdfium-Bau, kein OCR (ob eines gebraucht wird, klaert #289).

  ## Grenzen

  Ein PDF ohne Textebene (etwa ein Scan) ist ein klarer Fehler
  (`upstream-error`), kein leerer Text. Den markierten Text eines
  Highlights liefert der Schnitt der Zeichenboxen mit dem Rechteck der
  Annotation (Probe #278): ex_pdfium liest die QuadPoints nicht,
  mehrzeilige Highlights sind darum nur ungefaehr — gelesen wird von
  oben nach unten, Zeilen mit Leerzeichen verbunden. Nur
  /Subtype /Highlight zaehlt als Highlight; Unterstreichungen und
  Notizen bleiben unberuecksichtigt.
  """

  # Frame-Grenze des Connector-Protokolls (Sidecar.Frame.max_bytes/0):
  # groesserer extrahierter Text ist ein zu grosses Dokument, kein Fehler
  # erst beim Versand.
  @max_bytes 1_048_576

  # Luecken zwischen Zeichenboxen: pdfium synthetisiert Leerzeichen ohne
  # eigene Box; ab diesem Anteil der Schriftgroesse zaehlt eine Luecke
  # als Wortgrenze.
  @word_gap_factor 0.2

  @type highlight :: %{page: pos_integer(), text: String.t(), comment: String.t()}

  @doc """
  Liest das PDF unter `path` und rendert es als Text mit Seitenankern und
  Highlights. Erfolg: `{:ok, content}`. Fehler: `{:error, code, detail}`
  mit einem Code aus der geschlossenen Menge des Frame-Protokolls; der
  deutsche `detail` geht nur ins Connector-Log (CONTRACT.md §3).
  """
  @spec render(Path.t()) :: {:ok, String.t()} | {:error, String.t(), String.t()}
  def render(path) do
    with {:ok, doc} <- open(path),
         {:ok, content} <- content(doc) do
      :ok = ExPdfium.close(doc)
      {:ok, content}
    end
  rescue
    # Z. B. im Escript-Kontext: der NIF laesst sich aus dem Archiv nicht
    # per dlopen laden. Klarer Fehler statt Crash der Verbindung — die
    # Programmform fuer NIF-Connectoren entscheidet #288.
    exception ->
      {:error, "internal", "PDF-Lesung fehlgeschlagen: " <> to_string(exception.__struct__)}
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
        {:error, "internal", "PDF-Oeffnung fehlgeschlagen: " <> Kernel.inspect(reason)}
    end
  end

  defp content(doc) do
    with {:ok, count} <- page_count(doc),
         {:ok, pages} <- read_pages(doc, count),
         :ok <- require_text(pages) do
      highlights = read_highlights(doc, count)

      case assemble(pages, highlights) do
        content when byte_size(content) > @max_bytes ->
          {:error, "too-large", "extrahierter Text groesser als 1 MiB"}

        content ->
          {:ok, content}
      end
    end
  end

  defp page_count(doc) do
    case ExPdfium.page_count(doc) do
      {:ok, 0} ->
        {:error, "upstream-error", "PDF ohne Seiten"}

      {:ok, count} ->
        {:ok, count}

      {:error, reason} ->
        {:error, "internal", "Seitenzahl nicht lesbar: " <> Kernel.inspect(reason)}
    end
  end

  # [{Seitenzahl 1-basiert, Text}] — leere Seiten bleiben leer, der
  # Anker nennt sie trotzdem. pdfium trennt Zeilen mit \r\n; der Text
  # bekommt einheitlich \n.
  defp read_pages(doc, count) do
    pages =
      Enum.reduce_while(0..(count - 1)//1, {:ok, []}, fn index, {:ok, acc} ->
        case ExPdfium.extract_text(doc, index) do
          {:ok, text} ->
            {:cont,
             {:ok, [{index + 1, text |> String.replace("\r\n", "\n") |> String.trim()} | acc]}}

          {:error, reason} ->
            {:halt, {:error, "internal", "Seite nicht lesbar: " <> Kernel.inspect(reason)}}
        end
      end)

    case pages do
      {:ok, list} -> {:ok, Enum.reverse(list)}
      error -> error
    end
  end

  # Ein PDF, aus dem sich ueberhaupt kein Text ziehen laesst, ist ein
  # Scan ohne Textebene: klarer Fehler statt leeren Texts (Ticket #290,
  # kein OCR bis #289).
  defp require_text(pages) do
    if Enum.any?(pages, fn {_no, text} -> text != "" end) do
      :ok
    else
      {:error, "upstream-error", "PDF ohne Textebene (Scan ohne OCR, Ticket #289)"}
    end
  end

  # Highlights je Seite; innerhalb der Seite von oben nach unten, dann
  # von links nach rechts (Rechteck-Enden, nicht Baseline: das Rechteck
  # ist das Sortierkriterium, das pdfium liefert).
  defp read_highlights(doc, count) do
    highlights =
      for index <- 0..(count - 1)//1,
          {:ok, annotations} <- [ExPdfium.annotations(doc, index)],
          annotation <- annotations,
          annotation.type == :highlight do
        %{
          page: index + 1,
          text: marked_text(doc, index, annotation.bounds),
          comment: clean(annotation.contents),
          top: annotation.bounds && annotation.bounds.top,
          left: annotation.bounds && annotation.bounds.left
        }
      end

    Enum.sort_by(highlights, &{&1.page, -(&1.top || 0), &1.left || 0})
  end

  # Der markierte Text: Schnitt der Zeichenboxen mit dem Rechteck der
  # Annotation, gelesen oben nach unten, Zeilen mit Leerzeichen verbunden
  # (Probe #278 — QuadPoints liest ex_pdfium nicht).
  defp marked_text(_doc, _index, nil), do: ""

  defp marked_text(doc, index, rect) do
    case ExPdfium.chars(doc, index) do
      {:ok, chars} ->
        chars
        # Weißraum-Zeichen (pdfium meldet Zeilenumbrueche als eigene
        # Zeichen) faellen weg; Luecken und Zeilenwechsel setzt join_chars.
        |> Enum.reject(fn char -> char.char =~ ~r/\s/ end)
        |> Enum.filter(fn char -> char.bounds && overlap?(char.bounds, rect) end)
        |> sort_reading_order()
        |> join_chars()

      {:error, _reason} ->
        ""
    end
  end

  defp overlap?(box, rect) do
    box.left < rect.right and box.right > rect.left and
      box.bottom < rect.top and box.top > rect.bottom
  end

  # Lesereihenfolge: Baseline von oben nach unten (PDF-y wachst nach
  # oben), innerhalb der Zeile nach x. Die Baseline (origin) ist der
  # stabile Anker; ohne Origin dient die Boxmitte.
  defp sort_reading_order(chars) do
    Enum.sort_by(chars, fn char ->
      %{x: x, y: y} = pen_position(char)
      {-y, x}
    end)
  end

  defp pen_position(%{origin: %{x: x, y: y}}), do: %{x: x, y: y}

  defp pen_position(%{bounds: %{left: left, right: right, bottom: bottom, top: top}}),
    do: %{x: (left + right) / 2, y: (bottom + top) / 2}

  defp pen_position(_char), do: %{x: 0, y: 0}

  # Zeichen zu Text: eine Luecke ab einem Fuenftel der Schriftgroesse
  # wird zum Leerzeichen (pdfium synthetisiert Leerzeichen ohne Box),
  # ein Zeilenwechsel ebenfalls.
  defp join_chars(chars), do: join_chars(chars, [], nil)

  defp join_chars([], acc, _previous) do
    acc |> Enum.reverse() |> :erlang.iolist_to_binary()
  end

  defp join_chars([char | rest], acc, previous) do
    join_chars(rest, [char.char, separate(previous, char) | acc], char)
  end

  defp separate(nil, _char), do: ""

  defp separate(previous, char) do
    cond do
      same_line?(previous, char) and word_gap?(previous, char) -> " "
      same_line?(previous, char) -> ""
      true -> " "
    end
  end

  defp same_line?(previous, char) do
    %{y: previous_y} = pen_position(previous)
    %{y: current_y} = pen_position(char)
    abs(current_y - previous_y) < 1
  end

  defp word_gap?(previous, char) do
    char.bounds.left - previous.bounds.right > previous.font_size * @word_gap_factor
  end

  # ------------------------------------------------------------------
  # Darstellung
  # ------------------------------------------------------------------

  defp assemble(pages, highlights) do
    text = Enum.map_join(pages, "\n\n", fn {no, text} -> "[Seite #{no}]\n" <> text end)

    case highlights do
      [] ->
        text

      _entries ->
        text <> "\n\n---\n\nHighlights:\n\n" <> Enum.map_join(highlights, "\n", &highlight_line/1)
    end
  end

  defp highlight_line(highlight) do
    "- Seite #{highlight.page}: " <> marked_part(highlight) <> comment_part(highlight)
  end

  defp marked_part(%{text: text}) when text != "", do: "„#{text}“"

  defp marked_part(_highlight), do: "(keinen markierten Text erkannt)"

  defp comment_part(%{comment: ""}), do: ""

  defp comment_part(%{comment: comment}), do: " — Kommentar: " <> comment

  # Kommentare koennen mehrzeilig sein; fuer eine Zeile je Highlight wird
  # Weißraum zu einem Leerzeichen zusammengezogen.
  defp clean(nil), do: ""

  defp clean(text), do: text |> String.split() |> Enum.join(" ")
end
