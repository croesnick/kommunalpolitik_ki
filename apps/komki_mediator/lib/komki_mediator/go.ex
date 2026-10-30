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
  Legt die Anfrage ab und wartet auf die Antwort. Liefert die vorgelegte
  Freigabe, `:refused` (Nein) oder `:timeout`.
  """
  @spec await(config(), map()) :: {:release, map()} | :refused | :timeout
  def await(%{dir: dir, timeout_ms: timeout_ms}, %{"call_hash" => hash} = request) do
    File.mkdir_p!(dir)
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    expires_at = System.os_time(:second) + div(timeout_ms, 1000)
    request_file = Path.join(dir, hash <> ".request.json")
    answer_file = Path.join(dir, hash <> ".answer.json")
    _ = File.rm(answer_file)

    write_atomic(request_file, Map.put(request, "expires_at", expires_at))

    try do
      poll(answer_file, deadline)
    after
      _ = File.rm(request_file)
      _ = File.rm(answer_file)
    end
  end

  # Map.get statt Schluessel-Muster: KomkiPolicy.JSON typisiert Objekte als
  # %{}, Dialyzer verwirft sonst den Match (wie in KomkiMediator.Journal).
  defp poll(answer_file, deadline) do
    case read_answer(answer_file) do
      {:ok, answer} ->
        if Map.get(answer, "schema") == "komki-release/1", do: {:release, answer}, else: :refused

      :none ->
        if System.monotonic_time(:millisecond) >= deadline do
          :timeout
        else
          Process.sleep(@poll_ms)
          poll(answer_file, deadline)
        end
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
