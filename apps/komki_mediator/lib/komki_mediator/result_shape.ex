defmodule KomkiMediator.ResultShape do
  @moduledoc """
  Gate 2, erster Schritt (Connector-Vertrag §6.2.1): die Connector-Antwort
  muss genau der Ergebnisform aus §5.2 entsprechen. Die Formen sind
  geschlossen — fehlende oder zusaetzliche Schluessel und andere Typen
  als String (bzw. Liste von Strings bei `labels`) sind ein Verstoss. Ein
  Verstoss fuehrt zur Zurueckhaltung (`redacted`); die Antwort erreicht
  den Modellkontext dann nicht.
  """

  @ris_hit ~w(datum nummer sitzung titel top_id url)
  @ris_session ~w(datum gremium sitzung sitzung_id uhrzeit url)
  @ris_agenda_top ~w(nummer titel top_id)
  @web_hit ~w(snippet title url)
  @vault_hit ~w(labels note_id title)

  @doc "Prueft `result` gegen die Ergebnisform von Connector `id`, Operation `op`."
  @spec check(String.t(), String.t(), map()) :: :ok | {:error, String.t()}
  def check("ris", "search", result), do: list_result(result, ["abrufdatum"], @ris_hit)

  def check("ris", "show", result),
    do: object(result, ~w(abrufdatum datum nummer sitzung text titel top_id url))

  # #516: meetings in a window, and one meeting's public agenda.
  def check("ris", "sessions", result), do: list_result(result, ["abrufdatum"], @ris_session)

  def check("ris", "agenda", result),
    do:
      list_field(
        result,
        "tops",
        ~w(abrufdatum datum gremium sitzung sitzung_id uhrzeit url),
        @ris_agenda_top
      )

  def check("web", "search", result), do: list_result(result, ["abrufdatum"], @web_hit)
  def check("vault", "search", result), do: list_result(result, [], @vault_hit)
  def check("vault", "read", result), do: object(result, ~w(content labels note_id title))
  def check("vault", "write_test", result), do: object(result, ~w(labels note_id))

  # Durchstich #409, belegt im Wegwerf-Lauf: Die Quittung des ratsprojekte-Connectors
  # ist bewusst leer — kein Schlüssel, keine Kennung, keine Fortnummer,
  # nichts aus dem Hub (Szene 11: enumeration). Nur der feste Status und
  # die Labels, die der Vermittler selbst per context.assigned_label
  # verglichen hat.
  def check("ratsprojekte", "fakt_vorschlagen", result), do: object(result, ~w(labels status))

  # #419: the stand file as text, nothing else. Its labels come from the
  # manifest, the connector reports none.
  def check("ratsprojekte", "stand_lesen", result), do: object(result, ["stand"])
  def check(id, op, _result), do: {:error, "keine Ergebnisform fuer #{id}.#{op}"}

  # Objekt mit Trefferliste unter "results" plus weiteren Feldern.
  defp list_result(result, extra, hit_keys), do: list_field(result, "results", extra, hit_keys)

  # Object with a list of objects under `key`, plus further string fields.
  defp list_field(result, key, extra, item_keys) do
    case result do
      %{^key => items} when is_list(items) ->
        with :ok <- object(Map.delete(result, key), extra) do
          Enum.find_value(items, :ok, &hit_error(&1, item_keys))
        end

      _ ->
        {:error, key <> " fehlt oder ist keine Liste"}
    end
  end

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
