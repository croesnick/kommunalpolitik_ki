defmodule KomkiMediator.Go do
  @moduledoc """
  Interaktives GO fuer eine blockierte Ausgabe (Ticket #98, R.6.2,
  CONTRACT §4.6). Bietet der Remedy-Katalog einer emit- oder store-Ablehnung eine
  Aktionsfreigabe fuer den exakten Call an (`aktionsfreigabe`, scope
  `call`), legt der Vermittler eine Anfrage ab und wartet begrenzt auf die
  Antwort der nutzenden Person (`komki go`), sofern jemand zuhoert
  (`listening?/1`: eine Session mit angedocktem Terminal, `KomkiCli.GoWatcher`).

  Dateien unter `<base>/mediator/go/` (pi kann dort weder lesen noch
  schreiben, also auch kein GO ausstellen):

  * `<call_hash>.request.json` — vom Vermittler: Operation (`emit` oder
    `store`), Tool, Parameter (die Vorschau), Blocker, die Bausteine des
    Call-Hashs, `expires_at`.
  * `<call_hash>.answer.json` — von `komki go`: eine Aktionsfreigabe
    `komki-release/1` oder `{"go": false}`.

  Beide Dateien verschwinden nach dem Warten, mit jeder Antwort und auch
  ohne. Ohne Antwort bis zum Ablauf bleibt es beim deny (kein stiller
  Fallback). Ob die Freigabe gilt, entscheidet allein die Engine
  (`KomkiPolicy.Derive.decide_with_release/5`).
  """

  @poll_ms 250

  # Die zustaendige Stelle einer Aktionsfreigabe (CONTRACT §2.6): im
  # Einzelnutzer-Betrieb erteilt die nutzende Person das GO selbst.
  @authority "nutzende-person"

  @doc "Beobachter, der ein GO ausstellt (`authority` der Freigabe)."
  @spec authority() :: String.t()
  def authority, do: @authority

  @typedoc "GO-Konfiguration der Umgebung: Verzeichnis und Wartezeit."
  @type config() :: %{dir: Path.t(), timeout_ms: non_neg_integer()}

  # Herzschlag des Zuhoerers (KomkiCli.GoWatcher), hoechstens so alt.
  @listener_max_age_s 5

  @doc "Pfad des Herzschlags, den eine Session mit angedocktem Terminal erneuert."
  @spec listener_path(Path.t()) :: Path.t()
  def listener_path(dir), do: Path.join(dir, "listener")

  @doc """
  Hoert jemand zu? Nur dann lohnt das Warten: ohne Zuhoerer (`komki run`,
  abgedockte Session) bleibt es beim sofortigen deny.
  """
  @spec listening?(Path.t()) :: boolean()
  def listening?(dir) do
    case File.stat(listener_path(dir), time: :posix) do
      {:ok, %File.Stat{mtime: mtime}} -> System.os_time(:second) - mtime <= @listener_max_age_s
      {:error, _} -> false
    end
  end

  @doc "Call-Hash der angebotenen Aktionsfreigabe (scope `call`) oder nil."
  @spec offered(term()) :: String.t() | nil
  def offered(remedies) when is_list(remedies) do
    Enum.find_value(remedies, fn remedy ->
      Enum.find_value(Map.get(remedy, "transitions", []), fn
        %{"type" => "aktionsfreigabe", "scope" => "call", "call_hash" => hash} -> hash
        _ -> nil
      end)
    end)
  end

  def offered(_remedies), do: nil

  @doc """
  Das angebotene Offenlegungsfreigabe-Wort im Katalog (scope `call`) oder
  nil: Call-Hash, Ausgabeart und Ziellabel der Lockerung (§ 4.9, #423) —
  alles, was das GO tragen muss (R.6.2).
  """
  @spec offered_offenlegung(term()) ::
          %{call_hash: String.t(), ausgabeart: String.t(), ziellabel: [String.t()]} | nil
  def offered_offenlegung(remedies) when is_list(remedies) do
    Enum.find_value(remedies, fn remedy ->
      Enum.find_value(Map.get(remedy, "transitions", []), fn
        %{"type" => "offenlegungsfreigabe", "scope" => "call"} = transition ->
          %{
            call_hash: transition["call_hash"],
            ausgabeart: transition["ausgabeart"],
            ziellabel: transition["ziellabel"]
          }

        _ ->
          nil
      end)
    end)
  end

  def offered_offenlegung(_remedies), do: nil

  @doc """
  Legt die Anfrage ab und wartet auf die Antwort. Liefert die vorgelegte
  Freigabe, `:refused` (Nein) oder `:timeout`.

  Eine Anfrage mit Teilen (`kind: offenlegungsfreigabe`, #423) wird mit
  einer Auswahl beantwortet (`{:selection, ids}`): Die nutzende Person
  wählt, welche Teile den Raum verlassen — eine Abwahl ergibt ein neues
  Ereignis mit neuem Hash, deshalb baut der Vermittler die Freigabe erst
  danach über den reduzierten Call.
  """
  @spec await(config(), map()) ::
          {:release, map()} | {:selection, [String.t()]} | :refused | :timeout
  def await(%{dir: dir, timeout_ms: timeout_ms}, %{"call_hash" => hash} = request) do
    File.mkdir_p!(dir)
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    expires_at = System.os_time(:second) + div(timeout_ms, 1000)
    request_file = Path.join(dir, hash <> ".request.json")
    answer_file = Path.join(dir, hash <> ".answer.json")
    _ = File.rm(answer_file)

    write_atomic(request_file, Map.put(request, "expires_at", expires_at))

    try do
      poll(answer_file, deadline, request)
    after
      _ = File.rm(request_file)
      _ = File.rm(answer_file)
    end
  end

  # Map.get statt Schluessel-Muster: KomkiPolicy.JSON typisiert Objekte als
  # %{}, Dialyzer verwirft sonst den Match (wie in KomkiMediator.Journal).
  # Eine Offenlegungs-Anfrage nimmt nur die Auswahl-Antwort an (die
  # Freigabe baut der Vermittler selbst, über den Hash des reduzierten
  # Calls); jede andere Antwort ist ein Nein, nie ein GO.
  defp poll(answer_file, deadline, %{"kind" => "offenlegungsfreigabe"} = request) do
    case read_answer(answer_file) do
      {:ok, answer} when is_map(answer) ->
        selection_answer(answer, request)

      _other_answer_or_none ->
        poll_deadline(answer_file, deadline, request)
    end
  end

  defp poll(answer_file, deadline, request) do
    case read_answer(answer_file) do
      {:ok, answer} ->
        if Map.get(answer, "schema") == "komki-release/1", do: {:release, answer}, else: :refused

      :none ->
        poll_deadline(answer_file, deadline, request)
    end
  end

  # Nur die gueltige Auswahl-Antwort ist ein GO (§ 4.9): eine ungueltige
  # Auswahl oder eine Antwort in einer anderen Form ist ein Nein.
  defp selection_answer(answer, request) do
    if Map.get(answer, "schema") == "komki-go-answer/1" and Map.get(answer, "go") == true do
      case valid_selection(answer, request) do
        nil -> :refused
        ids -> {:selection, ids}
      end
    else
      :refused
    end
  end

  defp poll_deadline(answer_file, deadline, request) do
    if System.monotonic_time(:millisecond) >= deadline do
      :timeout
    else
      Process.sleep(@poll_ms)
      poll(answer_file, deadline, request)
    end
  end

  # Die Auswahl nennt nur Kennungen aus der Anfrage; Unbekanntes,
  # Duplikate und eine leere Auswahl sind ein Nein — nichts verlässt
  # den Raum, wenn kein Teil gewählt bleibt.
  defp valid_selection(answer, request) do
    ids = Map.get(answer, "teile", [])
    valid = request |> Map.get("teile", []) |> Enum.map(& &1["id"])

    if is_list(ids) and ids != [] and Enum.all?(ids, &(&1 in valid)) and
         ids == Enum.uniq(ids) do
      ids
    else
      nil
    end
  end

  # Eine unlesbare Antwort ist ein Nein, nie ein GO.
  defp read_answer(file) do
    case File.read(file) do
      {:ok, content} ->
        case KomkiPolicy.JSON.parse(content) do
          {:ok, answer} when is_map(answer) -> {:ok, answer}
          _ -> {:ok, %{"go" => false}}
        end

      {:error, _} ->
        :none
    end
  end

  # -------------------------------------------------------------------------
  # Gegenseite: komki go (ausserhalb der pi-Sandbox)
  # -------------------------------------------------------------------------

  @release_window_s 300

  @doc "Offene, noch nicht abgelaufene Anfragen, aelteste zuerst."
  @spec pending(Path.t()) :: [map()]
  def pending(dir) do
    now = System.os_time(:second)

    dir
    |> Path.join("*.request.json")
    |> Path.wildcard()
    |> Enum.flat_map(fn file ->
      with {:ok, content} <- File.read(file),
           {:ok, request} when is_map(request) <- KomkiPolicy.JSON.parse(content),
           {:ok, expires_at} when is_integer(expires_at) and expires_at > now <-
             Map.fetch(request, "expires_at") do
        [request]
      else
        _ -> []
      end
    end)
    |> Enum.sort_by(& &1["expires_at"])
  end

  @doc """
  Beantwortet eine Anfrage: `true` schreibt eine Aktionsfreigabe fuer genau
  diesen Call (frische Nonce, Frische-Fenster ab jetzt), `false` ein Nein.
  Ist die Anfrage inzwischen abgelaufen (der Vermittler hat sie entfernt),
  bleibt sie unbeantwortet: `:expired`.
  """
  @spec answer(Path.t(), map(), boolean()) :: :ok | :expired
  def answer(dir, %{"call_hash" => hash} = request, go?) do
    if File.exists?(Path.join(dir, hash <> ".request.json")) do
      term = if go?, do: release_for(request, System.os_time(:second)), else: %{"go" => false}
      write_atomic(Path.join(dir, hash <> ".answer.json"), term)
    else
      :expired
    end
  end

  @doc """
  Beantwortet eine Offenlegungs-Anfrage mit einer Teileauswahl (#423):
  `teile` nennt die Kennungen aus der Anfrage, die den Raum verlassen
  dürfen — leer oder ungültig ist ein Nein. Die Freigabe selbst baut der
  Vermittler über den reduzierten Call; die Antwort ist nur die
  menschliche Entscheidung.
  """
  @spec answer_selection(Path.t(), map(), [String.t()]) :: :ok | :expired
  def answer_selection(dir, %{"call_hash" => hash} = request, selection) do
    valid_ids = request |> Map.get("teile", []) |> Enum.map(& &1["id"])

    if File.exists?(Path.join(dir, hash <> ".request.json")) do
      answer =
        if selection != [] and Enum.all?(selection, &(&1 in valid_ids)) do
          %{"schema" => "komki-go-answer/1", "go" => true, "teile" => Enum.uniq(selection)}
        else
          %{"go" => false}
        end

      write_atomic(Path.join(dir, hash <> ".answer.json"), answer)
    else
      :expired
    end
  end

  @doc """
  Offenlegungsfreigabe `komki-release/2` fuer den (gegebenenfalls
  reduzierten) Call einer Anfrage (CONTRACT §2.6, §4.9, #423): der
  Vermittler baut sie nach der Auswahl — eine Abwahl ergibt ein neues
  Ereignis mit neuem Hash, und genau dieses Ereignis legt die Freigabe
  fest (R.6.2). `call_hash` und `content_digest` gehoeren zum reduzierten
  Call, `ausgabeart` und `ziellabel` kommen aus der Anfrage.
  """
  @spec offenlegung_release_for(map(), map(), integer()) :: map()
  def offenlegung_release_for(
        request,
        %{call_hash: call_hash, content_digest: content_digest},
        now
      ) do
    nonce = Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)

    %{
      "schema" => "komki-release/2",
      "release_id" => "go-" <> nonce,
      "kind" => "offenlegungsfreigabe",
      "operation" => request["operation"],
      "object" => request["object"],
      "workspace" => request["workspace"],
      "content_digest" => content_digest,
      "call_hash" => call_hash,
      "scope" => request["scope"],
      "authority" => request["authority"],
      "valid_from" => now,
      "valid_until" => now + @release_window_s,
      "nonce" => "n-" <> nonce,
      "ausgabeart" => request["ausgabeart"],
      "ziellabel" => request["ziellabel"]
    }
  end

  @doc "Aktionsfreigabe `komki-release/1` fuer eine Anfrage (CONTRACT §2.6)."
  @spec release_for(map(), integer()) :: map()
  def release_for(request, now) do
    nonce = Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)

    %{
      "schema" => "komki-release/1",
      "release_id" => "go-" <> nonce,
      "kind" => "aktionsfreigabe",
      "operation" => request["operation"],
      "object" => request["object"],
      "workspace" => request["workspace"],
      "content_digest" => request["content_digest"],
      "call_hash" => request["call_hash"],
      "scope" => request["scope"],
      "authority" => request["authority"],
      "valid_from" => now,
      "valid_until" => now + @release_window_s,
      "nonce" => "n-" <> nonce
    }
  end

  @doc "Schreibt JSON atomar (tmp + rename), damit der Leser nie eine halbe Datei sieht."
  @spec write_atomic(Path.t(), map()) :: :ok
  def write_atomic(file, term) do
    tmp = file <> ".tmp"
    File.write!(tmp, KomkiPolicy.JSON.canonical(term))
    File.rename!(tmp, file)
  end
end
