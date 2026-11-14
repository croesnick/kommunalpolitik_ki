defmodule KomkiConnectorRis.Top do
  @moduledoc """
  Reine Helfer fuer Upstream-Daten: oeffentliche TOPs auswaehlen, IDs
  pruefen, Textbloecke in Klartext wandeln, Datum kuerzen.

  **Fail-closed:** Ein TOP gilt nur dann als oeffentlich, wenn die API
  `"restricted": false` am TOP und `"protectedpart": false` an seinem
  Sitzungsteil liefert. Fehlt ein Feld oder hat es einen anderen Wert,
  behandelt der Connector den TOP als nicht-oeffentlich.
  """

  @id_pattern ~r/^[A-Za-z0-9_-]{1,64}$/
  @top_id_pattern ~r/^(\d{1,18})-\d{1,18}$/

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

  @doc "Textbloecke als Klartext: Ueberschrift, Leerzeile, Inhalt."
  @spec text(map()) :: String.t()
  def text(detail) do
    detail["textblocks"]
    |> list()
    |> Enum.filter(&is_map/1)
    |> Enum.map(fn block ->
      [string(block["caption"]), plain(string(block["content"]))]
      |> Enum.reject(&(&1 == ""))
      |> Enum.join("\n\n")
    end)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n\n")
  end

  @doc "Erste zehn Zeichen, wenn sie ein ISO-Datum sind, sonst leer."
  @spec date(term()) :: String.t()
  def date(<<day::binary-size(10), _::binary>>) do
    if Regex.match?(~r/^\d{4}-\d{2}-\d{2}$/, day), do: day, else: ""
  end

  def date(_), do: ""

  @doc "String-Wert oder leer (Upstream-Felder koennen fehlen)."
  @spec string(term()) :: String.t()
  def string(value) when is_binary(value), do: utf8(value)
  def string(_), do: ""

  # Inhalt kommt als Base64-kodiertes HTML (wie in Ratsinfo.Store); ist er
  # kein Base64 oder ergibt das Dekodat kein UTF-8, wird er als HTML genommen.
  defp plain(""), do: ""

  defp plain(content) do
    html =
      case Base.decode64(content) do
        {:ok, decoded} -> if String.valid?(decoded), do: decoded, else: content
        :error -> content
      end

    html
    |> String.replace(~r/<[^>]*>/, " ")
    |> decode_entities()
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
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
