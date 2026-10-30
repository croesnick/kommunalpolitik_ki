defmodule KomkiCli.GoSteps do
  @moduledoc """
  `komki go` (Ticket #98): offene GO-Anfragen des Vermittlers zeigen und je
  Anfrage fragen, ob genau dieser Aufruf einmal laufen darf.

  Die Vorschau zeigt Werkzeug, Parameter und den Grund der Sperre. Sie
  erscheint im Terminal der nutzenden Person, ausserhalb der pi-Sandbox.
  Enter oder Dateiende heisst Nein. Ein GO gilt nur fuer den gezeigten
  Aufruf, einmal und fuer fuenf Minuten; ob es greift, entscheidet der
  Vermittler mit der Engine. Dateiformat und Freigabe stehen in
  `KomkiMediator.Go`.

  Geht der Aufruf an Empfaenger ausserhalb des Rechners, nennt die
  Vorschau sie und warnt vor dem Existenz-Leck (Ticket #217): Schon der
  Aufruf selbst zeigt ihnen, dass und wann aus diesem Arbeitsraum gefragt
  wird, auch wenn die Parameter harmlos aussehen. Die Empfaenger stammen
  aus Γ (`registry.json`, Beobachter der Umgebung des Connectors).
  """

  alias KomkiConnector.Manifest
  alias KomkiMediator.Go

  # Beobachter, die zum Arbeitsraum selbst gehoeren (wie KomkiCli.Raumbild).
  @intern ["nutzende-person", "pi-agent"]

  @names %{"brave-search" => "Brave (Websuche)", "ris-betreiber" => "Betreiber des RIS"}

  @typedoc "Ein- und Ausgabe (in Tests ersetzbar)."
  @type ui() :: %{say: (String.t() -> term()), confirm: (String.t(), boolean() -> boolean())}

  @doc "Beantwortet alle offenen Anfragen unter `<base>/mediator/go`."
  @spec run(Path.t(), ui()) :: {String.t(), 0}
  def run(base, ui) do
    dir = Path.join([base, "mediator", "go"])

    case Go.pending(dir) do
      [] ->
        {"keine offenen GO-Anfragen\n", 0}

      requests ->
        environments = environments(base)
        results = Enum.map(requests, &answer(dir, &1, ui, environments))
        given = Enum.count(results, &(&1 == :go))
        {"#{given} von #{length(results)} Anfragen freigegeben\n", 0}
    end
  end

  defp answer(dir, request, ui, environments) do
    ui.say.(describe(request, leak_recipients(request, environments)))
    go? = ui.confirm.("GO für genau diesen Aufruf?", false)

    case Go.answer(dir, request, go?) do
      :ok when go? ->
        :go

      :ok ->
        :no

      :expired ->
        ui.say.("abgelaufen, der Vermittler hat schon abgelehnt")
        :expired
    end
  end

  @doc """
  Vorschau einer Anfrage (mehrzeilig). `recipients` sind die Empfaenger
  ausserhalb des Rechners; sind es welche, steht die Warnung zum
  Existenz-Leck dabei.
  """
  @spec describe(map(), [String.t()]) :: String.t()
  def describe(request, recipients \\ []) do
    params =
      request["params"]
      |> Enum.sort()
      |> Enum.map_join("\n", fn {key, value} -> "    " <> key <> ": " <> inspect(value) end)

    """

    Gesperrter Aufruf (Beleg #{request["decision_id"]})
      Werkzeug:  #{request["tool"]}
    #{action(request)}  Parameter:
    #{params}
      Gesperrt:  #{Enum.join(request["blockers"], ", ")}
    #{leak(recipients)}  Ein GO gilt nur für genau diesen Aufruf, einmal, fünf Minuten lang.\
    """
  end

  # Speichern braucht immer ein GO (Ticket #205): keine Bindung erlaubt
  # `store` von sich aus.
  defp action(%{"operation" => "store"}),
    do: "  Aktion:    speichern — jedes Schreiben braucht dein GO\n"

  defp action(_request), do: ""

  defp leak([]), do: ""

  defp leak(recipients) do
    names = Enum.map_join(recipients, ", ", &Map.get(@names, &1, &1))

    """
      Sichtbar für: #{names}
      Schon der Aufruf selbst zeigt #{names}, dass und wann aus diesem
      Arbeitsraum gefragt wird, auch wenn die Parameter harmlos aussehen.
    """
  end

  @doc """
  Empfaenger ausserhalb des Rechners fuer ein Connector-Tool: die Beobachter
  der Umgebung seines Manifests laut Γ, ohne nutzende Person und Agent.
  Unbekanntes Tool oder fehlendes Γ: keine.
  """
  @spec recipients(String.t() | nil, map()) :: [String.t()]
  def recipients(tool, environments) when is_binary(tool) do
    with {:ok, manifest, _op} <- Manifest.by_tool(tool),
         %{"observers" => observers} when is_list(observers) <-
           Map.get(environments, manifest.environment) do
      observers |> Enum.reject(&(&1 in @intern)) |> Enum.sort()
    else
      _ -> []
    end
  end

  def recipients(_tool, _environments), do: []

  # Ein emit-GO gibt nur das Erzeugen im Raum frei; nach draussen geht die
  # Anfrage erst mit transfer bzw. store (#298), dort steht die Warnung.
  defp leak_recipients(%{"operation" => "emit"}, _environments), do: []
  defp leak_recipients(request, environments), do: recipients(request["tool"], environments)

  defp environments(base) do
    with {:ok, content} <- File.read(Path.join([base, "mediator", "registry.json"])),
         {:ok, %{"environments" => envs}} when is_map(envs) <- JSON.decode(content) do
      envs
    else
      _ -> %{}
    end
  end
end
