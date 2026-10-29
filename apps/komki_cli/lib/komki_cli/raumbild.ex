defmodule KomkiCli.Raumbild do
  @moduledoc """
  Das Raumbild für die pi-Oberfläche (Ticket #242): welcher Raum, welcher
  Zweck, welche Labels und ob Anfragen nach draußen offen sind. komki
  schreibt es vor jedem pi-Start als `raum.json` neben die Anzeige
  (`KomkiCli.Anzeige`); die Extension zeigt es in Kopfzeile, Fußzeile und
  `/raum`.

  Quellen: `room.json` (B_W und Zweck), der Γ-Export `registry.json`
  (Empfängerkreise der Bindungen, Beobachter) und der Label-Store
  (Bezeichnungen). Das Raumbild ist reine Anzeige. Was pi darf, entscheidet
  weiter der Vermittler mit der Engine; „nach draußen“ beschreibt nur, wen
  der Empfängerkreis aller Bindungen in B_W einschließt.

  Ins Modell gelangt nichts davon: Die Extension zeichnet es nur.
  """

  alias KomkiCli.{Config, Gamma, LabelStore, StartContract}
  alias KomkiMediator.Templates

  @schema "komki-raum/1"

  # Beobachter, die zum Arbeitsraum selbst gehören. Alle anderen sind
  # Empfänger außerhalb des Rechners.
  @intern ["nutzende-person", "pi-agent"]

  @doc "Liest die Instanzdateien; fehlt etwas, bleibt das Feld leer."
  @spec load(Config.t()) :: map()
  def load(%Config{} = cfg) do
    room = read_json(StartContract.default_path(cfg.base_dir))
    registry = read_json(Gamma.registry_path(cfg))
    build(room, registry, &bezeichnung(Gamma.db_path(cfg), &1))
  end

  @doc """
  Baut das Raumbild aus Raum-Term, Γ-Export und einer Funktion, die zu
  einer Bindung die Bezeichnung liefert (oder nil). Rein.
  """
  @spec build(map() | nil, map() | nil, (String.t() -> String.t() | nil)) :: map()
  def build(room, registry, bezeichnung) do
    bw = workspace_bindings(room)
    registry = registry || %{}
    bindings = Map.get(registry, "bindings", %{})

    %{
      "schema" => @schema,
      "raum" => raum(bw),
      "zweck" => purpose(room),
      "labels" =>
        Enum.map(bw, fn id ->
          %{
            "id" => id,
            "bezeichnung" => bezeichnung.(id),
            "intern" => internal?(Map.get(bindings, id))
          }
        end),
      "nach_draussen" => outward(bw, bindings, Map.get(registry, "observers", []))
    }
  end

  @doc "JSON für die Extension (eine Zeile, mit Zeilenende)."
  @spec encode(map()) :: String.t()
  def encode(raumbild), do: JSON.encode!(raumbild) <> "\n"

  defp workspace_bindings(%{"workspace_bindings" => bw}) when is_list(bw), do: Enum.sort(bw)
  defp workspace_bindings(_room), do: []

  # Die beiden Referenzräume aus den Vorlagen haben Namen; jeder andere
  # B_W ist ein eigener Raum ohne Namen.
  defp raum([]), do: nil

  defp raum(bw) do
    cond do
      bw == Enum.sort(Templates.recherche_bindings()) -> "recherche"
      bw == Enum.sort(Templates.vertraulich_bindings()) -> "vertraulich"
      true -> nil
    end
  end

  defp purpose(%{"facts" => %{"purpose" => %{"value" => value}}}) when is_binary(value),
    do: value

  defp purpose(_room), do: nil

  defp internal?(%{"readers" => readers}) when is_list(readers),
    do: readers != [] and Enum.all?(readers, &(&1 in @intern))

  defp internal?(_binding), do: nil

  # Ein Empfänger außerhalb ist offen, wenn ihn der Empfängerkreis jeder
  # Bindung in B_W einschließt (recipient_inclusion der Engine). Ohne B_W
  # bietet der Raum keine Connector-Operationen an: nichts ist offen.
  defp outward(bw, bindings, observers) do
    for observer <- Enum.sort(observers), observer not in @intern do
      open? =
        bw != [] and
          Enum.all?(bw, fn id ->
            observer in (bindings |> Map.get(id, %{}) |> Map.get("readers", []))
          end)

      %{"empfaenger" => observer, "offen" => open?}
    end
  end

  defp bezeichnung(db, id) do
    if File.regular?(db) do
      case LabelStore.show_binding(db, id) do
        {:ok, %{bezeichnung: text}} -> text
        {:error, _} -> nil
      end
    end
  end

  defp read_json(path) do
    with {:ok, content} <- File.read(path),
         {:ok, map} when is_map(map) <- JSON.decode(content) do
      map
    else
      _ -> nil
    end
  end
end
