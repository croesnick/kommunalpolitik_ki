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

  @entities %{
    "amp" => "&",
    "lt" => "<",
    "gt" => ">",
    "quot" => "\"",
    "apos" => "'",
    "nbsp" => " "
  }

  defp decode_entities(text) do
    Regex.replace(~r/&(#\d{1,7}|#x[0-9a-fA-F]{1,6}|[a-z]+);/, text, fn whole, name ->
      entity(name) || whole
    end)
  end

  defp entity("#x" <> hex), do: codepoint(String.to_integer(hex, 16))
  defp entity("#" <> dec), do: codepoint(String.to_integer(dec))
  defp entity(name), do: Map.get(@entities, name)

  defp codepoint(n) when n in 0x20..0xD7FF or n in 0xE000..0x10FFFF, do: <<n::utf8>>
  defp codepoint(_), do: nil

  # JSON verlangt UTF-8; Altbestaende in Latin-1 werden umkodiert.
  defp utf8(bin) do
    if String.valid?(bin), do: bin, else: :unicode.characters_to_binary(bin, :latin1)
  end

  defp list(value) when is_list(value), do: value
  defp list(_), do: []
end
