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
  Unterhaltung samt Kontext fort. Deshalb bekommt jede Session ein eigenes
  Verzeichnis unter `pi-home/sessions` (`open_session/2`), und komki hält
  fest, unter welchem B_W sie lief (`<base>/run/sessions/<name>.json`,
  außerhalb von pi-home, das pi beschreiben darf). Fortsetzen geht nur in
  einem Raum, der mindestens so streng ist.

  Innerhalb von pi gäbe es weitere Wege zu einer anderen Session:
  `/resume` und `/import` (Ticket #295). Das Profil der Session gibt unter
  `pi-home/sessions` nur ihr eigenes Verzeichnis frei
  (`KomkiCli.Profile`), die Extension in pi bricht den Wechsel dorthin
  zusätzlich mit einem Hinweis ab. `/new`, `/fork` und `/clone` legen ihre
  Dateien im selben Verzeichnis an, also im Raum dieser Session; zu ihnen
  darf `/resume` wechseln.

  Den Wechsel belegt das Journal: Der Vermittler hält bei jedem Start das
  B_W fest, mit dem er entscheidet (`tool: "workspace"`).
  """

  alias KomkiCli.{Channel, Config, Gamma, Mediator, Pi, StartContract}
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

  @doc "Pfad der Raum-Markierung einer Session (Name ihres Verzeichnisses)."
  @spec marker_path(Config.t(), String.t()) :: Path.t()
  def marker_path(%Config{} = cfg, name),
    do: Path.join([Channel.run_dir(cfg), "sessions", name <> ".json"])

  @doc """
  Öffnet das Verzeichnis für `komki session` und hält den Raum fest. Neu:
  ein frisches Verzeichnis. `--continue`: das jüngste mit einer
  Unterhaltung, wenn der Raum mindestens so streng ist wie der, in dem sie
  lief. Fehlt die Markierung, ist das unbekannt: dann nein.

  Läuft nur, wenn keine Session läuft. Leere Verzeichnisse (Session ohne
  Unterhaltung) räumt der Aufruf vorher weg.
  """
  @spec open_session(Config.t(), boolean()) ::
          {:ok, Path.t()} | {:error, String.t(), pos_integer()}
  def open_session(%Config{} = cfg, continue?) do
    prune_sessions(cfg)

    with {:ok, room} <- read_room(cfg),
         current = room["workspace_bindings"],
         {:ok, name} <- pick_session(cfg, current, continue?) do
      dir = Path.join(Pi.sessions_root(cfg), name)
      File.mkdir_p!(dir)
      write_json(marker_path(cfg, name), %{"workspace_bindings" => Enum.sort(current)})
      write_json(current_path(cfg), %{"session" => name})
      {:ok, dir}
    end
  end

  @doc """
  Verzeichnis der zuletzt geöffneten Session, für den Start von pi im
  Pane. Prüft den Raum noch einmal: Wurde seit `open_session/2` gelockert,
  startet die Session nicht.
  """
  @spec session_dir(Config.t()) :: {:ok, Path.t()} | {:error, String.t(), pos_integer()}
  def session_dir(%Config{} = cfg) do
    with {:ok, name} <- current_session(cfg),
         {:ok, previous} <- read_marker(cfg, name),
         {:ok, room} <- read_room(cfg),
         :ok <- continue_into(room["workspace_bindings"], previous) do
      {:ok, Path.join(Pi.sessions_root(cfg), name)}
    else
      :missing -> {:error, "kein Session-Verzeichnis geöffnet: 'komki session' neu starten", 2}
      error -> error
    end
  end

  defp pick_session(_cfg, _current, false), do: {:ok, new_session_name()}

  defp pick_session(cfg, current, true) do
    case last_conversation(cfg) do
      nil ->
        {:error,
         "keine frühere Session in " <> Pi.sessions_root(cfg) <> "; ohne --continue starten", 2}

      name ->
        with {:ok, previous} <- read_marker(cfg, name),
             :ok <- continue_into(current, previous) do
          {:ok, name}
        else
          :missing ->
            {:error,
             "Für die letzte Session ist nicht festgehalten, in welchem Raum sie lief. " <>
               "Starte eine neue Session ohne --continue.", 2}

          error ->
            error
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

  defp write_room(cfg, room, bindings),
    do:
      write_json(
        StartContract.default_path(cfg.base_dir),
        Map.put(room, "workspace_bindings", bindings)
      )

  # Eine laufende Session arbeitet nach einem verschärfenden Wechsel im
  # strengeren Raum weiter; ihre Markierung zieht mit.
  defp mark_if_running(cfg, bindings, deps) do
    with true <- deps.session_running?.(cfg),
         {:ok, name} <- current_session(cfg) do
      write_json(marker_path(cfg, name), %{"workspace_bindings" => Enum.sort(bindings)})
    else
      _ -> :ok
    end
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

  # Verzeichnisnamen: UTC-Zeit des Starts auf die Mikrosekunde, sortierbar.
  # Andere Namen unter pi-home/sessions (etwa Dateien von vor #295) zählen
  # nicht als Session.
  @session_name ~r/\A\d{4}-\d\d-\d\dT\d\d-\d\d-\d\d-\d{6}Z\z/

  defp new_session_name,
    do: Calendar.strftime(DateTime.utc_now(:microsecond), "%Y-%m-%dT%H-%M-%S-%fZ")

  defp session_names(cfg) do
    case File.ls(Pi.sessions_root(cfg)) do
      {:ok, names} -> names |> Enum.filter(&Regex.match?(@session_name, &1)) |> Enum.sort()
      {:error, _} -> []
    end
  end

  # pi legt eine Session-Datei erst mit der ersten Nachricht an.
  defp last_conversation(cfg) do
    cfg
    |> session_names()
    |> Enum.reverse()
    |> Enum.find(fn name ->
      case File.ls(Path.join(Pi.sessions_root(cfg), name)) do
        {:ok, files} -> Enum.any?(files, &String.ends_with?(&1, ".jsonl"))
        {:error, _} -> false
      end
    end)
  end

  defp prune_sessions(cfg) do
    for name <- session_names(cfg),
        File.rmdir(Path.join(Pi.sessions_root(cfg), name)) == :ok,
        do: File.rm(marker_path(cfg, name))

    :ok
  end

  defp current_path(cfg), do: Path.join(Channel.run_dir(cfg), "session-current.json")

  defp current_session(cfg) do
    with {:ok, raw} <- File.read(current_path(cfg)),
         {:ok, %{"session" => name}} when is_binary(name) <- decode_object(raw),
         true <- Regex.match?(@session_name, name) do
      {:ok, name}
    else
      _ -> :missing
    end
  end

  defp write_json(path, term) do
    File.mkdir_p!(Path.dirname(path))
    tmp = path <> ".tmp"
    File.write!(tmp, KomkiPolicy.JSON.canonical(term))
    File.rename!(tmp, path)
  end

  defp read_marker(cfg, name) do
    with {:ok, raw} <- File.read(marker_path(cfg, name)),
         {:ok, %{"workspace_bindings" => bindings}} when is_list(bindings) <-
           decode_object(raw) do
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
