defmodule KomkiConnectorRis.Top do
  @moduledoc """
  Reine Helfer fuer Upstream-Daten: oeffentliche TOPs auswaehlen, IDs
  pruefen, Textbloecke in Klartext wandeln, Datum kuerzen.

  **Fail-closed:** Ein TOP gilt nur dann als oeffentlich, wenn die API
  `"restricted": false` am TOP und `"protectedpart": false` an seinem
  Sitzungsteil liefert. Fehlt ein Feld oder hat es einen anderen Wert,
  behandelt der Connector den TOP als nicht-oeffentlich.

  **Budgets (#486/#487):** Textbloecke werden vor der Verarbeitung auf
  Bytes begrenzt, einzeln und als Summe einer Antwort; ein Block ueber
  dem Budget lehnt die ganze Antwort ab, statt still gekuerzt zu werden.
  `text/2` fragt vor jedem Block die Restfrist ab, und alle
  Upstream-Felder verlieren ihre C0/C1-Steuerzeichen und eine
  ueberlange Laenge.
  """

  @id_pattern ~r/^[A-Za-z0-9_-]{1,64}$/
  @top_id_pattern ~r/^(\d{1,18})-\d{1,18}$/

  # Byte-Budgets der Textverarbeitung (#486): je Block und je Antwort.
  # Das Strukturprofil der Aufnahme 20261101T112819Z kennt hoechstens
  # drei Textbloecke je TOP, echte Inhalte liegen Kilobyte-range; die
  # ehemalige Tag-Regex entgleiste ab ~5 MiB pro Block. 64 KiB je Block
  # und 192 KiB je Antwort liegen weit ueber dem Beobachteten.
  @max_block_bytes 65_536
  @max_text_bytes 196_608

  # Kurzfelder (Nummer, Titel, Sitzung, Block-Ueberschrift): laenger als
  # 1 000 Zeichen wurde kein oeffentlicher Titel beobachtet (Strukturprofil:
  # hoechstens 472). Gekappt wird mit Marker, damit ein Zitat den Schnitt
  # zeigt (#487).
  @max_field_chars 1_000

  # C0-Steuerzeichen ausser Tab/CR/LF, DEL und die C1-Gruppe — derselbe
  # Vorrat wie KomkiCli.Terminal.sanitize/1 (#487): was eine
  # Terminal-Ausgabe faelschen koennte, soll im Kontext gar nicht erst
  # ankommen.
  @controls ~r/[\x00-\x08\x0B-\x1F\x7F\x{80}-\x{9F}]/u

  # Entity-Syntax fuer decode_entities/1: die Zahl-Formen und Namen, die
  # Grossbuchstaben und Ziffern tragen duerfen (&Uuml;, &sup2;, &frac12;).
  @entity_pattern ~r/&(#\d{1,7}|#x[0-9a-fA-F]{1,6}|[a-zA-Z][a-zA-Z0-9]*);/

  @doc "Oeffentliche TOPs einer Sitzung (Reihenfolge der Tagesordnung)."
  @spec public_items(map()) :: [map()]
  def public_items(meeting) do
    for %{"protectedpart" => false, "agendaitems" => items} when is_list(items) <-
          list(meeting["parts"]),
        item <- items,
        public?(item),
        valid_id?(item["id"]),
        do: item
  end

  @doc "Nur `restricted: false` ist oeffentlich."
  @spec public?(term()) :: boolean()
  def public?(%{"restricted" => false}), do: true
  def public?(_), do: false

  @doc "Upstream-ID passt zum Parameter-Muster des Manifests."
  @spec valid_id?(term()) :: boolean()
  def valid_id?(id), do: is_binary(id) and Regex.match?(@id_pattern, id)

  @doc ~s(Sitzungs-ID aus einer TOP-ID der Form "meetingId-agendaItemId".)
  @spec meeting_id(String.t()) :: {:ok, pos_integer()} | :error
  def meeting_id(top_id) do
    case Regex.run(@top_id_pattern, top_id) do
      [_, meeting] -> {:ok, String.to_integer(meeting)}
      nil -> :error
    end
  end

  @typedoc "Restfrist in Millisekunden (`Api.remaining`), `:infinity` ohne Frist."
  @type remaining :: (-> non_neg_integer() | :infinity)

  @typep text_result :: {:ok, String.t()} | {:error, :budget} | {:error, :deadline}

  @doc """
  Textbloecke als Klartext: Ueberschrift, Leerzeile, Inhalt.

  Vor jedem Block fragt `remaining` die Restfrist ab (`Api.remaining`,
  #486): 0 bricht ab. Ein Block ueber dem Byte-Budget lehnt die ganze
  Antwort ab — Kuerzen wuerde Zitate still schwaechen.
  """
  @spec text(map()) :: text_result()
  @spec text(map(), remaining()) :: text_result()
  def text(detail, remaining \\ fn -> :infinity end)

  def text(detail, remaining) do
    detail["textblocks"]
    |> list()
    |> Enum.filter(&is_map/1)
    |> Enum.reduce_while({:ok, 0, []}, fn block, {:ok, total, acc} ->
      content = block["content"]
      size = if is_binary(content), do: byte_size(content), else: 0

      cond do
        remaining.() == 0 -> {:halt, {:error, :deadline}}
        size > @max_block_bytes -> {:halt, {:error, :budget}}
        total + size > @max_text_bytes -> {:halt, {:error, :budget}}
        true -> {:cont, {:ok, total + size, [block_text(block) | acc]}}
      end
    end)
    |> finish_text()
  end

  defp finish_text({:ok, _total, blocks}) do
    {:ok, blocks |> Enum.reverse() |> Enum.reject(&(&1 == "")) |> Enum.join("\n\n")}
  end

  defp finish_text({:error, _} = error), do: error

  defp block_text(block) do
    [string(block["caption"]), plain(block["content"])]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n\n")
  end

  @doc "Erste zehn Zeichen, wenn sie ein ISO-Datum sind, sonst leer."
  @spec date(term()) :: String.t()
  def date(<<day::binary-size(10), _::binary>>) do
    if Regex.match?(~r/^\d{4}-\d{2}-\d{2}$/, day), do: day, else: ""
  end

  def date(_), do: ""

  @doc """
  String-Wert oder leer (Upstream-Felder koennen fehlen); C0/C1-Steuerzeichen
  entfallen und ueberlange Felder werden mit Marker gekappt (#487):
  Upstream-Felder sind unbegrenzt und nicht neutralisiert.
  """
  @spec string(term()) :: String.t()
  def string(value) when is_binary(value), do: value |> utf8() |> strip_controls() |> cap()
  def string(_), do: ""

  # Kappen erst nach dem Control-Strip, damit Steuerzeichen nicht als
  # Feldlaenge zaehlen. Der Byte-Test ist der schnelle Pfad: bis 1 000
  # Bytes ist die Zeichenzahl hoechstens 1 000.
  defp cap(text) when byte_size(text) <= @max_field_chars, do: text
  defp cap(text), do: if(String.length(text) <= @max_field_chars, do: text, else: cut(text))

  defp cut(text), do: String.slice(text, 0, @max_field_chars) <> "…"

  # Inhalt kommt als Base64-kodiertes HTML (wie in Ratsinfo.Store); ist er
  # kein Base64 oder ergibt das Dekodat kein UTF-8, wird er als HTML genommen.
  # Tags entfernt ein einziger linearer Lauf statt der Regex, die bei
  # grossen Bloecken in PCRE entgleiste (#486).
  defp plain(""), do: ""

  defp plain(content) when is_binary(content) do
    content
    |> utf8()
    |> decode64_or_raw()
    |> strip_controls()
    |> strip_tags()
    |> decode_entities()
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
  end

  defp plain(_), do: ""

  defp decode64_or_raw(content) do
    case Base.decode64(content) do
      {:ok, decoded} -> if String.valid?(decoded), do: decoded, else: content
      :error -> content
    end
  end

  defp strip_controls(html), do: String.replace(html, @controls, "")

  # Ein einziger linearer Lauf statt der Regex, die bei grossen Bloecken in
  # PCRE entgleiste (#486): Ein '<' oeffnet ein Tag bis zum NAECHSTEN '>',
  # auch ueber weitere '<' im Inneren — wie die alte Regex ~r/<[^>]*>/.
  # Kommt nie ein '>', bleibt der Lauf wortgetreu stehen (auch wie bisher).
  # Der Puffer ist Iodata: Anhängen kopiert nichts, der Lauf bleibt linear.
  defp strip_tags(html) do
    case String.split(html, "<") do
      [text] -> text
      [first | rest] -> first <> tags(rest, [])
    end
  end

  defp tags([], offen), do: offen |> Enum.reverse() |> IO.iodata_to_binary()

  defp tags([segment | rest], offen) do
    case String.split(segment, ">", parts: 2) do
      [_tag, text] -> " " <> text <> tags(rest, [])
      [_] -> tags(rest, ["<" <> segment | offen])
    end
  end

  # Benannte Entities der TOP-Texte. Der Vorrat ist absichtlich begrenzt und
  # hier dokumentiert (#547): der XML-Kern, der komplette Latin-1-Block von
  # HTML 4 (HTMLlat1, in Codepunkt-Reihenfolge) und die Satz- und
  # Waehrungszeichen, die in deutschen Gremientexten stehen (Anfuehrungs-
  # zeichen, Gedankenstriche, Ellipse, Euro). Griechische, mathematische und
  # seltene Zeichen fehlen bewusst: Unbekanntes bleibt roh stehen, das
  # Pruefskript priv/ris_tagesordnung.exs zaehlt es als ungeloest auf.
  # `shy` ist ein Layout-Hinweis (weiche Trennstelle), kein Text, und
  # faellt deshalb weg — in beiden Schreibweisen, siehe codepoint/1.
  @entities %{
    # XML-Kern
    "amp" => "&",
    "lt" => "<",
    "gt" => ">",
    "quot" => "\"",
    "apos" => "'",
    "nbsp" => " ",
    # Latin-1 (HTMLlat1)
    "iexcl" => "¡",
    "cent" => "¢",
    "pound" => "£",
    "curren" => "¤",
    "yen" => "¥",
    "brvbar" => "¦",
    "sect" => "§",
    "uml" => "¨",
    "copy" => "©",
    "ordf" => "ª",
    "laquo" => "«",
    "not" => "¬",
    "shy" => "",
    "reg" => "®",
    "macr" => "¯",
    "deg" => "°",
    "plusmn" => "±",
    "sup2" => "²",
    "sup3" => "³",
    "acute" => "´",
    "micro" => "µ",
    "para" => "¶",
    "middot" => "·",
    "cedil" => "¸",
    "sup1" => "¹",
    "ordm" => "º",
    "raquo" => "»",
    "frac14" => "¼",
    "frac12" => "½",
    "frac34" => "¾",
    "iquest" => "¿",
    "Agrave" => "À",
    "Aacute" => "Á",
    "Acirc" => "Â",
    "Atilde" => "Ã",
    "Auml" => "Ä",
    "Aring" => "Å",
    "AElig" => "Æ",
    "Ccedil" => "Ç",
    "Egrave" => "È",
    "Eacute" => "É",
    "Ecirc" => "Ê",
    "Euml" => "Ë",
    "Igrave" => "Ì",
    "Iacute" => "Í",
    "Icirc" => "Î",
    "Iuml" => "Ï",
    "ETH" => "Ð",
    "Ntilde" => "Ñ",
    "Ograve" => "Ò",
    "Oacute" => "Ó",
    "Ocirc" => "Ô",
    "Otilde" => "Õ",
    "Ouml" => "Ö",
    "times" => "×",
    "Oslash" => "Ø",
    "Ugrave" => "Ù",
    "Uacute" => "Ú",
    "Ucirc" => "Û",
    "Uuml" => "Ü",
    "Yacute" => "Ý",
    "THORN" => "Þ",
    "szlig" => "ß",
    "agrave" => "à",
    "aacute" => "á",
    "acirc" => "â",
    "atilde" => "ã",
    "auml" => "ä",
    "aring" => "å",
    "aelig" => "æ",
    "ccedil" => "ç",
    "egrave" => "è",
    "eacute" => "é",
    "ecirc" => "ê",
    "euml" => "ë",
    "igrave" => "ì",
    "iacute" => "í",
    "icirc" => "î",
    "iuml" => "ï",
    "eth" => "ð",
    "ntilde" => "ñ",
    "ograve" => "ò",
    "oacute" => "ó",
    "ocirc" => "ô",
    "otilde" => "õ",
    "ouml" => "ö",
    "divide" => "÷",
    "oslash" => "ø",
    "ugrave" => "ù",
    "uacute" => "ú",
    "ucirc" => "û",
    "uuml" => "ü",
    "yacute" => "ý",
    "thorn" => "þ",
    "yuml" => "ÿ",
    # Satz- und Waehrungszeichen (HTMLspecial-Auswahl)
    "bdquo" => "„",
    "ldquo" => "“",
    "rdquo" => "”",
    "sbquo" => "‚",
    "lsquo" => "‘",
    "rsquo" => "’",
    "ndash" => "–",
    "mdash" => "—",
    "hellip" => "…",
    "euro" => "€",
    "dagger" => "†",
    "Dagger" => "‡",
    "permil" => "‰",
    "lsaquo" => "‹",
    "rsaquo" => "›",
    "trade" => "™",
    "minus" => "−",
    "bull" => "•",
    "OElig" => "Œ",
    "oelig" => "œ",
    "Scaron" => "Š",
    "scaron" => "š",
    "Yuml" => "Ÿ"
  }

  defp decode_entities(text) do
    Regex.replace(@entity_pattern, text, fn whole, name -> entity(name) || whole end)
  end

  defp entity("#x" <> hex), do: codepoint(String.to_integer(hex, 16))
  defp entity("#" <> dec), do: codepoint(String.to_integer(dec))
  defp entity(name), do: Map.get(@entities, name)

  # Die weiche Trennstelle (U+00AD) ist Layout wie ihr benanntes Gegenstueck
  # &shy;: Sie entfaellt, egal ob als Dezimal- oder Hex-Form geschrieben.
  defp codepoint(0xAD), do: ""

  defp codepoint(n) when n in 0x20..0xD7FF or n in 0xE000..0x10FFFF, do: <<n::utf8>>
  defp codepoint(_), do: nil

  # JSON verlangt UTF-8; Altbestaende in Latin-1 werden umkodiert.
  defp utf8(bin) do
    if String.valid?(bin), do: bin, else: :unicode.characters_to_binary(bin, :latin1)
  end

  defp list(value) when is_list(value), do: value
  defp list(_), do: []
end
