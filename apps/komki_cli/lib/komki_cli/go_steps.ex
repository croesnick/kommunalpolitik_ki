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

  Eine Offenlegungsfreigabe (#423, Szene 13) ist kein gewoehnliches GO:
  Der Text verlaesst einen vertraulichen Raum und wird dem Vorstand
  offengelegt. Die Vorschau sagt das in einem eigenen Satz, nennt alle
  Empfaenger des Ziels und zeigt die Teile einzeln — abgewaehlte Teile
  verlassen den Raum nicht. Die Auswahl geschieht VOR dem GO (ein
  abgewaehltes Teil ist ein neues Ereignis mit neuem Hash, R.6.2); das
  Haeckchen im Hub kaeme zu spaet.
  """

  alias KomkiConnector.Manifest
  alias KomkiMediator.Go

  # Beobachter, die zum Arbeitsraum selbst gehoeren (wie KomkiCli.Raumbild).
  @intern ["nutzende-person", "pi-agent"]

  # Die Empfänger des Hub-Bestands mit sprechenden Namen im Freigabefenster
  # (Szene 11, Szene 13).
  @names %{
    "brave-search" => "Brave (Websuche)",
    "ris-betreiber" => "Betreiber des RIS",
    "fraktion" => "Fraktion",
    "vorstand" => "Vorstand",
    "nextcloud-betreiber" => "Betreiber der Nextcloud (Ordner für den Stand)",
    "sicherung" => "Sicherung (Time Machine)"
  }

  @typedoc "Ein- und Ausgabe (in Tests ersetzbar)."
  @type ui() :: %{
          say: (String.t() -> term()),
          confirm: (String.t(), boolean() -> boolean()),
          select: (String.t() -> String.t())
        }

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
    ui.say.(describe(request, recipients(request["tool"], environments)))

    if offenlegung?(request) do
      answer_offenlegung(dir, request, ui)
    else
      answer_simple(dir, request, ui)
    end
  end

  defp answer_simple(dir, request, ui) do
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

  # Teileauswahl vor dem GO (#423): Die Auswahl nennt Nummern der Teile,
  # die den Raum verlassen duerfen; Enter uebernimmt alle. Erst danach
  # fragt das GO — die Antwort gilt genau fuer die ausgewaehlten Teile.
  defp answer_offenlegung(dir, request, ui) do
    selection = ui.select.("Teile, die den Raum verlassen dürfen (z. B. 1,3 — Enter = alle):")
    ids = ids_for_selection(request, selection)

    go? =
      if ids == nil do
        false
      else
        ui.confirm.(
          "GO: Ich lege die ausgewählten Teile bewusst gegenüber dem Vorstand offen.",
          false
        )
      end

    case Go.answer_selection(dir, request, ids || []) do
      :ok when go? ->
        ui.say.("Offenlegung erteilt — sie gilt nur für diesen Aufruf, einmal.")
        :go

      :ok ->
        :no

      :expired ->
        ui.say.("abgelaufen, der Vermittler hat schon abgelehnt")
        :expired
    end
  end

  # Auswahl "1, 3" (oder "1,3") zu Teil-Kennungen; unbekannte Nummern
  # machen die Auswahl ungueltig (nil -> Nein), Enter wählt alle.
  defp ids_for_selection(request, selection) do
    choices = request["teile"]

    case String.trim(selection || "") do
      "" ->
        Enum.map(choices, & &1["id"])

      typed ->
        typed_ids(choices, typed)
    end
  end

  # Auswahl "1, 3" (oder "1,3") zu Teil-Kennungen; jede unbekannte oder
  # doppelte Nummer macht die Auswahl ungueltig (nil -> Nein).
  defp typed_ids(choices, typed) do
    numbers =
      typed
      |> String.split(~r{[\s,]+}, trim: true)
      |> Enum.map(fn number -> Integer.parse(number) end)

    if Enum.all?(numbers, &match?({n, ""} when is_integer(n), &1)) do
      picked = Enum.map(numbers, fn {n, ""} -> n end)
      valid_nummern = Enum.map(choices, fn choice -> choice["nummer"] end)

      if Enum.all?(picked, &(&1 in valid_nummern)) and picked == Enum.uniq(picked) do
        choices |> Enum.filter(&(&1["nummer"] in picked)) |> Enum.map(& &1["id"])
      else
        nil
      end
    else
      nil
    end
  end

  defp offenlegung?(%{"kind" => "offenlegungsfreigabe"}), do: true
  defp offenlegung?(_request), do: false

  @doc """
  Vorschau einer Anfrage (mehrzeilig). `recipients` sind die Empfaenger
  ausserhalb des Rechners; sind es welche, steht die Warnung zum
  Existenz-Leck dabei. Eine Offenlegungsfreigabe zeigt zusaetzlich den
  Hinweis auf die Offenlegung, alle Empfaenger des Ziels und die Teile
  einzeln.
  """
  @spec describe(map(), [String.t()]) :: String.t()
  def describe(request, recipients \\ []) do
    params =
      request["params"]
      |> Enum.sort()
      |> Enum.map_join("\n", fn {key, value} ->
        "    " <> key <> ": " <> inspect(value)
      end)

    kopf(request, params, recipients) <>
      "  Ein GO gilt nur für genau diesen Aufruf, einmal, fünf Minuten lang."
  end

  defp kopf(%{"kind" => "offenlegungsfreigabe"} = request, params, _recipients) do
    """
    Gesperrter Aufruf (Beleg #{request["decision_id"]})
      Werkzeug:  #{request["tool"]}
    #{action(request)}#{offenlegung(request)}  Parameter:
    #{params}
    #{teile(request)}  Gesperrt:  #{Enum.join(request["blockers"], ", ")}
    """
  end

  defp kopf(request, params, recipients) do
    basis = """
    Gesperrter Aufruf (Beleg #{request["decision_id"]})
      Werkzeug:  #{request["tool"]}
    #{action(request)}  Parameter:
    #{params}
      Gesperrt:  #{Enum.join(request["blockers"], ", ")}
    """

    basis <> leak(recipients)
  end

  # Speichern braucht immer ein GO (Ticket #205): keine Bindung erlaubt
  # `store` von sich aus.
  defp action(%{"operation" => "store"}),
    do: "  Aktion:    speichern — jedes Schreiben braucht dein GO\n"

  defp action(_request), do: ""

  # Der Hinweis auf die Offenlegung (Szene 13): Ziel, alle Empfaenger und
  # was dieses GO bedeutet — mit den Namen aus @names.
  defp offenlegung(request) do
    empfaenger =
      request
      |> Map.get("empfaenger", [])
      |> Enum.map_join(", ", &Map.get(@names, &1, &1))

    """
      Ausgabe:   #{request["ausgabeart"]} (Lockerung auf #{Enum.join(request["ziellabel"], ", ")})
      Offenlegung: Ich lege den ausgewählten Text bewusst gegenüber dem Vorstand offen.
      Alle Empfänger: #{empfaenger}
    """
  end

  # Der genaue Text, Teil fuer Teil: die Vorschau zeigt jedes Teil mit
  # Nummer und vollstaendigem Inhalt — nichts wird gekuerzt (Szene 13).
  defp teile(request) do
    teile =
      request["params"]
      |> Map.get("teile", [])
      |> List.wrap()
      |> Enum.with_index(1)
      |> Enum.map_join("\n", fn {teil, nummer} ->
        "    #{nummer}. " <> String.replace(inspect(teil), "\\n", " ")
      end)

    """
      Teile:
    #{teile}
    """
  end

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
    with {:ok, manifest, op} <- Manifest.by_tool(tool),
         %{"observers" => observers} when is_list(observers) <-
           Map.get(environments, Manifest.environment(manifest, op)) do
      observers |> Enum.reject(&(&1 in @intern)) |> Enum.sort()
    else
      _ -> []
    end
  end

  def recipients(_tool, _environments), do: []

  defp environments(base) do
    with {:ok, content} <- File.read(Path.join([base, "mediator", "registry.json"])),
         {:ok, %{"environments" => envs}} when is_map(envs) <- JSON.decode(content) do
      envs
    else
      _ -> %{}
    end
  end
end
