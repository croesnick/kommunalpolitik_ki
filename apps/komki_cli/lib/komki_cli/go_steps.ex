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
  """

  alias KomkiMediator.Go

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
        results = Enum.map(requests, &answer(dir, &1, ui))
        given = Enum.count(results, &(&1 == :go))
        {"#{given} von #{length(results)} Anfragen freigegeben\n", 0}
    end
  end

  defp answer(dir, request, ui) do
    ui.say.(describe(request))
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

  @doc "Vorschau einer Anfrage (mehrzeilig)."
  @spec describe(map()) :: String.t()
  def describe(request) do
    params =
      request["params"]
      |> Enum.sort()
      |> Enum.map_join("\n", fn {key, value} -> "    " <> key <> ": " <> inspect(value) end)

    """

    Gesperrter Aufruf (Beleg #{request["decision_id"]})
      Werkzeug:  #{request["tool"]}
      Parameter:
    #{params}
      Gesperrt:  #{Enum.join(request["blockers"], ", ")}
      Ein GO gilt nur für genau diesen Aufruf, einmal, fünf Minuten lang.\
    """
  end
end
