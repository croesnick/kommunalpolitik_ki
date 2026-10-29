defmodule KomkiCli.Raum do
  @moduledoc """
  Raum anzeigen und wechseln (Ticket #268): `komki raum` und
  `komki raum recherche|vertraulich`.

  Ein Raum ist hier sein B_W, die `workspace_bindings` in
  `<base>/mediator/room.json`. Gewechselt wird nur zwischen den beiden
  Referenzräumen der Vorlage (`KomkiMediator.Templates`), nie mit einer
  getippten Liste. Beide teilen sich bisher die `workspace_id` und damit
  den GO-Stand. Nach RFC 0003 wären es zwei Arbeitsräume mit je festem
  B_W (Folgeticket #270). Ein eigener Raum (andere Bindungen oder ein
  Startvertrag `contract`, bis #214 ein zweites B_W) wird angezeigt, aber
  nicht umgestellt.

  Mehr Bindungen heißt strenger: Jede Bindung in B_W gilt für jede
  Operation (R.5.4, #213). Daraus folgen zwei Regeln:

    * **Verschärfen** (das neue B_W enthält das alte) geht jederzeit. Eine
      laufende Session arbeitet nach dem Neustart des Vermittlers im neuen
      Raum weiter, das Socket-Token bleibt (#216).
    * **Lockern** geht nur ohne laufende Session und ohne laufenden
      `komki run`. Sonst trüge der Kontext von pi Vertrauliches in einen
      Raum mit Weg nach draußen. Jeder Lauf hinterlegt dafür für seine Dauer
      eine Datei `<base>/run/runs/<pid>` (`track_run/2`).

  Dieselbe Gefahr hat `komki session --continue`: pi setzt die letzte
  Unterhaltung samt Kontext fort. Deshalb hält komki beim Start jeder
  Session fest, unter welchem B_W sie lief (`<base>/run/session-room.json`,
  außerhalb von pi-home, das pi beschreiben darf). Fortsetzen geht nur in
  einem Raum, der mindestens so streng ist.

  Den Wechsel belegt das Journal: Der Vermittler hält bei jedem Start das
  B_W fest, mit dem er entscheidet (`tool: "workspace"`).
  """

  alias KomkiCli.{Channel, Config, Gamma, Mediator, StartContract}
  alias KomkiMediator.Templates

  @descriptions %{
    "recherche" => "RIS, Websuche und öffentliche Notizen. Vertrauliche Notizen sind unsichtbar.",
    "vertraulich" =>
      "Auch vertrauliche Notizen. Nach draußen geht nichts ohne dein GO für den einzelnen Aufruf."
  }

  @typedoc "Abhängigkeiten, in Tests ersetzbar."
  @type deps :: %{
          session_running?: (Config.t() -> boolean()),
          run_active?: (Config.t() -> boolean()),
          mediator_running?: (Config.t() -> boolean()),
          restart: (Config.t() -> {:ok, term()} | {:error, String.t()})
        }

  @doc "Namen und B_W der Referenzräume."
  @spec rooms() :: %{String.t() => [String.t()]}
  def rooms do
    %{
      "recherche" => Templates.recherche_bindings(),
      "vertraulich" => Templates.vertraulich_bindings()
    }
  end

  @doc "Name des Referenzraums zu einem B_W, sonst `nil`."
  @spec name([String.t()] | nil) :: String.t() | nil
  def name(bindings) when is_list(bindings) do
    Enum.find_value(rooms(), fn {name, room} -> if same?(room, bindings), do: name end)
  end

  def name(_), do: nil

  @doc "Ob `strict` mindestens so streng ist wie `loose` (enthält alle Bindungen)."
  @spec at_least_as_strict?([String.t()], [String.t()]) :: boolean()
  def at_least_as_strict?(strict, loose),
    do: MapSet.subset?(MapSet.new(loose), MapSet.new(strict))

  @doc "`komki raum`: aktueller Raum mit Beschreibung."
  @spec show(Config.t()) :: {:raum, String.t()} | {:error, String.t(), pos_integer()}
  def show(%Config{} = cfg) do
    with {:ok, room} <- read_room(cfg) do
      {:raum, Enum.join(describe(room["workspace_bindings"]) ++ [switch_hint()], "\n")}
    end
  end

  @doc "`komki raum NAME`: in einen Referenzraum wechseln."
  @spec switch(Config.t(), String.t(), deps()) ::
          {:raum, String.t()} | {:error, String.t(), pos_integer()}
  def switch(%Config{} = cfg, target, deps \\ default_deps()) do
    with {:ok, bindings} <- target_bindings(target),
         {:ok, room} <- read_room(cfg),
         :ok <- reference_room(room),
         current = room["workspace_bindings"],
         :ok <- not_same(current, target),
         :ok <- loosening_allowed(cfg, current, bindings, deps),
         :ok <- bindings_in_gamma(cfg, bindings),
         :ok <- write_room(cfg, room, bindings),
         :ok <- mark_if_running(cfg, bindings, deps),
         {:ok, note} <- reload(cfg, deps) do
      {:raum,
       Enum.join(
         ["Raum        " <> name(current) <> " → " <> target] ++
           tl(describe(bindings)) ++ [note],
         "\n"
       )}
    end
  end

  @doc """
  Führt `fun` als `komki run` aus und hält den Lauf so lange unter
  `<base>/run/runs/<pid>` fest. Eine Lockerung wartet, bis er endet. Die
  Datei trägt die Kommandozeile des Prozesses: Lebt unter derselben
  Nummer später ein anderer Prozess, zählt er nicht als Lauf.
  """
  @spec track_run(Config.t(), (-> result)) :: result when result: term()
  def track_run(%Config{} = cfg, fun) do
    pid = System.pid()
    path = Path.join(runs_dir(cfg), pid)
    File.mkdir_p!(runs_dir(cfg))
    File.write!(path, command_of(pid))

    try do
      fun.()
    after
      File.rm(path)
    end
  end

  @doc "Ob gerade ein `komki run` dieser Instanz läuft (Prozess lebt noch)."
  @spec run_active?(Config.t()) :: boolean()
  def run_active?(%Config{} = cfg) do
    case File.ls(runs_dir(cfg)) do
      {:ok, pids} ->
        Enum.any?(pids, fn pid ->
          command = command_of(pid)
          command != "" and File.read(Path.join(runs_dir(cfg), pid)) == {:ok, command}
        end)

      {:error, _} ->
        false
    end
  end

  defp command_of(pid) do
    case System.cmd("/bin/ps", ["-p", pid, "-o", "command="], stderr_to_stdout: true) do
      {out, 0} -> String.trim(out)
      _ -> ""
    end
  end

  defp runs_dir(cfg), do: Path.join(Channel.run_dir(cfg), "runs")

  @doc "Pfad der Raum-Markierung der letzten Session."
  @spec marker_path(Config.t()) :: Path.t()
  def marker_path(%Config{} = cfg), do: Path.join(Channel.run_dir(cfg), "session-room.json")

  @doc """
  Hält das B_W des Raums fest, in dem eine Session startet oder
  fortgesetzt wird. Rufen nur `komki session` und ein verschärfender
  Wechsel; pi kann die Datei nicht schreiben.
  """
  @spec mark_session(Config.t()) :: :ok | {:error, String.t(), pos_integer()}
  def mark_session(%Config{} = cfg) do
    with {:ok, room} <- read_room(cfg) do
      write_marker(cfg, room["workspace_bindings"])
    end
  end

  @doc """
  Darf die letzte Session im aktuellen Raum fortgesetzt werden? Nur, wenn
  der Raum mindestens so streng ist wie der, in dem sie lief. Fehlt die
  Markierung (Session von vor #268), ist das unbekannt: dann nein.
  """
  @spec continue_allowed(Config.t()) :: :ok | {:error, String.t(), pos_integer()}
  def continue_allowed(%Config{} = cfg) do
    with {:ok, room} <- read_room(cfg) do
      case read_marker(cfg) do
        {:ok, previous} ->
          continue_into(room["workspace_bindings"], previous)

        :missing ->
          {:error,
           "Für die letzte Session ist nicht festgehalten, in welchem Raum sie lief. " <>
             "Starte eine neue Session ohne --continue.", 2}
      end
    end
  end

  defp continue_into(current, previous) do
    if at_least_as_strict?(current, previous),
      do: :ok,
      else:
        {:error,
         "Die letzte Session lief im Raum " <>
           label(previous) <>
           ". Im Raum " <>
           label(current) <>
           " fortgesetzt, käme ihr Kontext in einen Raum mit weniger Schutz. " <>
           "Starte eine neue Session ohne --continue oder wechsle zurück: komki raum " <>
           (name(previous) || "…"), 2}
  end

  # ---------------------------------------------------------------------------

  defp default_deps do
    %{
      session_running?: &KomkiCli.Steps.session_running?/1,
      run_active?: &run_active?/1,
      mediator_running?: &(Mediator.health(&1) == :ok),
      restart: &Mediator.restart/1
    }
  end

  defp target_bindings(target) do
    case Map.fetch(rooms(), target) do
      {:ok, bindings} ->
        {:ok, bindings}

      :error ->
        {:error,
         "Unbekannter Raum '" <> target <> "'. Es gibt: " <> Enum.join(room_names(), ", "), 2}
    end
  end

  defp read_room(cfg) do
    path = StartContract.default_path(cfg.base_dir)

    with {:ok, raw} <- File.read(path),
         {:ok, room} <- decode_object(raw) do
      {:ok, room}
    else
      _ -> {:error, "room.json nicht lesbar: " <> path <> " ('komki setup' legt sie an)", 2}
    end
  end

  defp reference_room(%{"contract" => _}),
    do:
      {:error,
       "Dieser Raum hat einen Startvertrag (contract in room.json) mit eigenem B_W. " <>
         "komki raum stellt ihn nicht um, bis beide zusammengeführt sind (#214).", 2}

  defp reference_room(room) do
    if name(room["workspace_bindings"]),
      do: :ok,
      else:
        {:error,
         "Eigener Raum (B_W " <>
           Enum.join(List.wrap(room["workspace_bindings"]), ", ") <>
           "). komki raum wechselt nur zwischen den Referenzräumen " <>
           Enum.join(room_names(), " und ") <> ".", 2}
  end

  defp not_same(current, target) do
    if name(current) == target,
      do: {:error, "Der Raum ist schon " <> target <> ".", 2},
      else: :ok
  end

  defp loosening_allowed(cfg, current, bindings, deps) do
    cond do
      at_least_as_strict?(bindings, current) ->
        :ok

      deps.session_running?.(cfg) ->
        {:error,
         "Eine Session läuft noch. Der Raum " <>
           label(bindings) <>
           " ist weniger streng, ihr Kontext käme dorthin mit. " <>
           "Beende die Session (in pi: /quit), dann noch einmal komki raum " <>
           name(bindings) <> ".", 2}

      deps.run_active?.(cfg) ->
        {:error,
         "Ein komki run läuft noch. Der Raum " <>
           label(bindings) <>
           " ist weniger streng, sein Kontext käme dorthin mit. " <>
           "Warte, bis er endet, dann noch einmal komki raum " <> name(bindings) <> ".", 2}

      true ->
        :ok
    end
  end

  # Dieselbe Quelle wie `komki up`: Γ aus dem Label-Store, geprüft über
  # die Engine (KomkiPolicy.Registry.compile/1). Fehlt eine Bindung, wird
  # nichts geschrieben.
  defp bindings_in_gamma(cfg, bindings) do
    with gamma when gamma in [:unchanged, :written] <- Gamma.sync(cfg),
         {:ok, raw} <- File.read(Gamma.registry_path(cfg)),
         {:ok, term} <- KomkiPolicy.JSON.parse(raw),
         {:ok, compiled} <- KomkiPolicy.Registry.compile(term) do
      case Enum.reject(bindings, &Map.has_key?(compiled.bindings, &1)) do
        [] -> :ok
        missing -> {:error, "Bindungen fehlen in Γ: " <> Enum.join(missing, ", "), 2}
      end
    else
      {:error, reason} when is_binary(reason) -> {:error, reason, 2}
      other -> {:error, "Γ nicht prüfbar: " <> inspect(other), 2}
    end
  end

  defp write_room(cfg, room, bindings) do
    path = StartContract.default_path(cfg.base_dir)
    tmp = path <> ".tmp"
    File.write!(tmp, KomkiPolicy.JSON.canonical(Map.put(room, "workspace_bindings", bindings)))
    File.rename!(tmp, path)
  end

  # Eine laufende Session arbeitet nach einem verschärfenden Wechsel im
  # strengeren Raum weiter; ihre Markierung zieht mit.
  defp mark_if_running(cfg, bindings, deps) do
    if deps.session_running?.(cfg), do: write_marker(cfg, bindings), else: :ok
  end

  defp reload(cfg, deps) do
    if deps.mediator_running?.(cfg) do
      case deps.restart.(cfg) do
        {:ok, _} ->
          {:ok,
           "Vermittler  neu gestartet, er entscheidet jetzt im neuen Raum." <>
             session_note(cfg, deps)}

        {:error, reason} ->
          {:error,
           "room.json ist umgestellt, der Neustart des Vermittlers scheiterte: " <> reason, 4}
      end
    else
      {:ok, "Vermittler  läuft nicht, beim nächsten Start gilt der neue Raum."}
    end
  end

  defp session_note(cfg, deps) do
    if deps.session_running?.(cfg),
      do:
        " Die laufende Session arbeitet weiter, die Anzeige in pi zeigt den Raum ab dem nächsten Start.",
      else: ""
  end

  defp write_marker(cfg, bindings) do
    path = marker_path(cfg)
    File.mkdir_p!(Path.dirname(path))
    tmp = path <> ".tmp"
    File.write!(tmp, KomkiPolicy.JSON.canonical(%{"workspace_bindings" => Enum.sort(bindings)}))
    File.rename!(tmp, path)
  end

  defp read_marker(cfg) do
    with {:ok, raw} <- File.read(marker_path(cfg)),
         {:ok, %{"workspace_bindings" => bindings}} when is_list(bindings) <- decode_object(raw) do
      {:ok, bindings}
    else
      _ -> :missing
    end
  end

  # Wie KomkiCli.StartContract: strikte Vorpruefung mit KomkiPolicy.JSON
  # (doppelte Schluessel, Nicht-JSON), der Term kommt aus dem stdlib-Decoder.
  # Die Policy-JSON-Spec typisiert Maps als leeres %{}, Dialyzer verwuerfe
  # sonst jedes Schluesselmuster.
  defp decode_object(raw) do
    with {:ok, _term} <- KomkiPolicy.JSON.parse(raw),
         {:ok, %{} = term} <- Elixir.JSON.decode(raw) do
      {:ok, term}
    else
      _ -> :error
    end
  end

  defp describe(bindings) do
    case name(bindings) do
      nil ->
        ["Raum        eigener Raum", "Labels      " <> Enum.join(List.wrap(bindings), ", ")]

      name ->
        ["Raum        " <> name, "            " <> Map.fetch!(@descriptions, name)]
    end
  end

  defp switch_hint, do: "Wechseln: komki raum " <> Enum.join(room_names(), " | ")

  defp label(bindings), do: name(bindings) || "eigener Raum"

  defp room_names, do: rooms() |> Map.keys() |> Enum.sort()

  defp same?(a, b), do: MapSet.new(a) == MapSet.new(b)
end
