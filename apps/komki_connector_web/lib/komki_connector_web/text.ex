defmodule KomkiConnectorWeb.Text do
  @moduledoc """
  Bereinigt Texte aus der Brave-Antwort: HTML-Tags entfernen (Brave
  markiert Treffer mit `<strong>`), Entities dekodieren, Leerraum
  zusammenfassen und auf eine Hoechstlaenge kuerzen.
  """

  @named %{
    "amp" => "&",
    "lt" => "<",
    "gt" => ">",
    "quot" => "\"",
    "apos" => "'",
    "nbsp" => " ",
    "auml" => "ä",
    "ouml" => "ö",
    "uuml" => "ü",
    "Auml" => "Ä",
    "Ouml" => "Ö",
    "Uuml" => "Ü",
    "szlig" => "ß",
    "ndash" => "–",
    "mdash" => "—",
    "hellip" => "…",
    "laquo" => "«",
    "raquo" => "»",
    "bdquo" => "„",
    "ldquo" => "“",
    "rdquo" => "”",
    "lsquo" => "‘",
    "rsquo" => "’",
    "euro" => "€"
  }

  @doc "Tags entfernen, Entities dekodieren, Leerraum normalisieren, kuerzen."
  @spec clean(String.t(), pos_integer()) :: String.t()
  def clean(text, max) when is_binary(text) do
    text
    |> strip_tags()
    |> decode_entities()
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
    |> String.slice(0, max)
  end

  # Erst Tags weg, dann dekodieren: ein kodiertes `&lt;b&gt;` bleibt so
  # als Text sichtbar und wird nicht zum Tag.
  defp strip_tags(text), do: String.replace(text, ~r/<[^>]*>/, "")

  defp decode_entities(text) do
    Regex.replace(~r/&(#[0-9]{1,7}|#[xX][0-9a-fA-F]{1,6}|[a-zA-Z]+);/, text, fn whole, ref ->
      decode(ref) || whole
    end)
  end

  defp decode("#x" <> hex), do: codepoint(String.to_integer(hex, 16))
  defp decode("#X" <> hex), do: codepoint(String.to_integer(hex, 16))
  defp decode("#" <> dec), do: codepoint(String.to_integer(dec))
  defp decode(name), do: Map.get(@named, name)

  # Ungueltige Codepoints (Surrogates, > U+10FFFF, NUL) bleiben unveraendert.
  defp codepoint(cp) when cp in 1..0xD7FF or cp in 0xE000..0x10FFFF, do: <<cp::utf8>>
  defp codepoint(_cp), do: nil
end
