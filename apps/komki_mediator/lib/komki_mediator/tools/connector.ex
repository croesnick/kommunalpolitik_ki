defmodule KomkiMediator.Tools.Connector do
  @moduledoc """
  Baustein fuer die sechs Connector-Tools: `use KomkiMediator.Tools.Connector,
  tool: "ris_search"` erzeugt ein anubis-Tool, dessen Parameter-Schema und
  Beschreibung zur Compile-Zeit aus `KomkiConnector.Manifest` stammen
  (einzige Quelle, Connector-Vertrag §5). Der Tool-Name ergibt sich aus dem
  Modulnamen (`RisSearch` -> `ris_search`); ein Abgleich zur Compile-Zeit
  verhindert Abweichungen.

  Abbildung des Manifest-Schemas: `string` mit `max_length` und
  `pattern` (als JSON-Schema-Angabe), `integer` mit `min`/`max` und
  `default`, Pflichtfelder als `required`. Die Muster prueft das Gate
  (`Sidecar.Params.check/3`), damit ein Verstoss als `error` mit
  PDR endet.

  `execute/2` entscheidet nichts selbst: der Aufruf geht unveraendert an
  `KomkiMediator.ConnectorGate.call/3`.
  """

  alias KomkiConnector.Manifest

  defmacro __using__(opts) do
    tool = Keyword.fetch!(opts, :tool)
    {:ok, manifest, op} = Manifest.by_tool(tool)
    spec = Map.fetch!(manifest.ops, op)

    expected =
      __CALLER__.module |> Module.split() |> List.last() |> Macro.underscore()

    if expected != tool do
      raise ArgumentError, "Modul #{inspect(__CALLER__.module)} passt nicht zu Tool #{tool}"
    end

    fields =
      for {name, field} <- Enum.sort(spec.params) do
        field_ast(name, field)
      end

    quote do
      use Anubis.Server.Component, type: :tool

      alias Anubis.Server.Response

      schema do
        unquote({:__block__, [], fields})
      end

      @impl true
      def description, do: unquote(spec.description)

      @impl true
      def execute(params, frame) do
        env = KomkiMediator.Env.for_call(frame)
        response = KomkiMediator.ConnectorGate.call(env, unquote(tool), params)
        {:reply, Response.json(Response.tool(), response), frame}
      end
    end
  end

  @doc false
  # Manifest-Feld -> Optionen des anubis-field-Makros (nur literale Werte;
  # ein kompiliertes Regex wird als Quelltext uebernommen).
  @spec field_opts(map()) :: keyword()
  def field_opts(%{type: :string} = field) do
    [required: Map.get(field, :required, true), max_length: field.max] ++
      if(field[:pattern], do: [pattern: Regex.source(field.pattern)], else: [])
  end

  def field_opts(%{type: :integer} = field) do
    [required: Map.get(field, :required, true), min: field.min, max: field.max] ++
      if(Map.has_key?(field, :default), do: [default: field.default], else: [])
  end

  # DURCHSTICH #409 (Wegwerf): Optionen des anubis-embeds_many-Makros; die
  # Item-Grenzen heissen dort min/max (Peri), nicht min_items/max_items.
  @spec list_opts(map()) :: keyword()
  def list_opts(field) do
    [
      required: Map.get(field, :required, true),
      min: Map.get(field, :min_items, 1),
      max: Map.get(field, :max_items, 8)
    ]
  end

  @doc false
  # AST eines Manifest-Feldes (String/Integer wie bisher); ein :list-Feld
  # (DURCHSTICH #409, Wegwerf: ein Ereignis mit Teilen — die Teile sind
  # eine geschlossene Liste von Objekten, Sidecar.Params prüft sie vor
  # der Engine; hier nur die Werbung ans Modell als zweite Schicht) wird
  # zu anubis embeds_many.
  @spec field_ast(String.t(), map()) :: Macro.t()
  def field_ast(name, %{type: :list} = field) do
    item_fields =
      for {item_name, item_spec} <- Enum.sort(Map.get(field, :items, %{})) do
        quote do
          field(
            unquote(String.to_atom(item_name)),
            unquote(item_spec.type),
            unquote(field_opts(item_spec))
          )
        end
      end

    quote do
      embeds_many unquote(String.to_atom(name)), unquote(list_opts(field)) do
        (unquote_splicing(item_fields))
      end
    end
  end

  def field_ast(name, field) do
    quote do
      field(unquote(String.to_atom(name)), unquote(field.type), unquote(field_opts(field)))
    end
  end
end
