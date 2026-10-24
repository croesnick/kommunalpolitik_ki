defmodule KomkiMediator.ResultShape do
  @moduledoc """
  Gate 2, erster Schritt (Connector-Vertrag §6.2.1): die Connector-Antwort
  muss genau der Ergebnisform aus §5.2 entsprechen. Die Formen sind
  geschlossen — fehlende oder zusaetzliche Schluessel und andere Typen
  als String (bzw. Liste von Strings bei `labels`) sind ein Verstoss. Ein
  Verstoss fuehrt zur Zurueckhaltung (`redacted`); die Antwort erreicht
  den Modellkontext dann nicht.
  """

  @ris_hit ~w(datum sitzung titel top_id url)
  @web_hit ~w(snippet title url)
  @vault_hit ~w(labels note_id title)

  @doc "Prueft `result` gegen die Ergebnisform von Connector `id`, Operation `op`."
  @spec check(String.t(), String.t(), map()) :: :ok | {:error, String.t()}
  def check("ris", "search", result), do: list_result(result, ["abrufdatum"], @ris_hit)

  def check("ris", "show", result),
    do: object(result, ~w(abrufdatum datum sitzung text titel top_id url))

  def check("web", "search", result), do: list_result(result, ["abrufdatum"], @web_hit)
  def check("vault", "search", result), do: list_result(result, [], @vault_hit)
  def check("vault", "read", result), do: object(result, ~w(content labels note_id title))
  def check("vault", "write_test", result), do: object(result, ~w(labels note_id))
  def check(id, op, _result), do: {:error, "keine Ergebnisform fuer #{id}.#{op}"}

  # Objekt mit Trefferliste unter "results" plus weiteren Feldern.
  defp list_result(%{"results" => hits} = result, extra, hit_keys) when is_list(hits) do
    with :ok <- object(Map.delete(result, "results"), extra) do
      Enum.find_value(hits, :ok, &hit_error(&1, hit_keys))
    end
  end

  defp list_result(_result, _extra, _hit_keys), do: {:error, "results fehlt oder ist keine Liste"}

  # nil fuer einen gueltigen Treffer, sonst der Fehler (fuer find_value).
  defp hit_error(hit, keys) do
    case object(hit, keys) do
      :ok -> nil
      error -> error
    end
  end

  defp object(map, keys) when is_map(map) do
    cond do
      Enum.sort(Map.keys(map)) != Enum.sort(keys) ->
        {:error, "Schluessel #{inspect(Enum.sort(Map.keys(map)))} statt #{inspect(keys)}"}

      not Enum.all?(map, &valid_field?/1) ->
        {:error, "Feld mit unzulaessigem Typ"}

      true ->
        :ok
    end
  end

  defp object(_other, _keys), do: {:error, "kein Objekt"}

  defp valid_field?({"labels", labels}), do: is_list(labels) and Enum.all?(labels, &is_binary/1)
  defp valid_field?({_key, value}), do: is_binary(value)
end
