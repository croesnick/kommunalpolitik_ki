defmodule KomkiMediator.TestHelpers do
  @moduledoc false

  # Wiederverwendbare Helfer fuer Tests: Provisionierung in ein temp-Verzeichnis,
  # Laden von Gamma/Raum und der Ping-Executor als Orakel.

  alias KomkiMediator.{Gamma, Room, Templates}

  @doc "Ein temporaeres Basisverzeichnis (hermetisch; Zufallssuffix gegen Restbestaende frueherer Laeufe)."
  def tmp_base(prefix \\ "komki-mediator-test-") do
    suffix = Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
    Path.join(System.tmp_dir!(), prefix <> suffix)
  end

  @doc "Provisioniert einen tmp-Basisraum und liefert das Basisverzeichnis zurueck."
  def provisioned_base do
    base = tmp_base()
    Templates.provision!(base)
    base
  end

  @doc "Laedt Gamma und Raum aus einem provisionierten Basisverzeichnis."
  def load_room_env(base) do
    {:ok, gamma} = Gamma.load(Path.join([base, "mediator", "registry.json"]))
    {:ok, room} = Room.load(Path.join(base, "mediator"))
    {gamma, room}
  end

  @doc "Ping-Executor wie das MCP-Tool ihn stellt (Vollzug nach Gate 1)."
  def ping_executor(gamma) do
    fn ->
      {:ok,
       %{
         "object_id" => "mediator-ping",
         "fassung_id" => KomkiMediator.Fassung.fassung_id(),
         "registry_id" => gamma.registry_id,
         "gamma_hash" => gamma.gamma_hash,
         "tools" => KomkiMediator.Fassung.tools()
       }}
    end
  end

  @doc "Executor für admit_document: liest die Raumdokument-Datei."
  def admit_executor(room, document_id) do
    fn ->
      path = Path.join(room.documents_dir, document_id <> ".md")

      case File.read(path) do
        {:ok, content} ->
          {:ok, %{"object_id" => document_id, "document_id" => document_id, "content" => content}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  # Jeder Journal-Eintrag ist ein kanonisches JSON-Dokument mit genau
  # einem finalen Newline; dies multi-line-Kanons folgen direkt
  # aufeinander. Grenze zwischen Eintraegen: "\n{\n" an Position Null tritt
  # nur am Record-Rand auf (interne Klammerausdruecke sind eingerueckt).
  def journal_records(path) do
    Enum.map(journal_chunks_raw(path), fn chunk ->
      {:ok, record} = KomkiPolicy.JSON.parse(chunk)
      record
    end)
  end

  def journal_chunks_raw(path), do: KomkiMediator.Journal.split_records(File.read!(path))

  @doc """
  Stoppt benannte Prozesse (Env, Journal) und startet sie frisch am
  Basisraum. `extra` ergaenzt die Umgebung (z. B. `connectors_dir`).
  """
  def restart_env(base, extra \\ %{}) do
    stop_named(KomkiMediator.Env)
    stop_named(KomkiMediator.Journal)

    journal_path = Path.join([base, "mediator", "journal", "pdr.jsonl"])
    {:ok, _journal} = KomkiMediator.Journal.start_link(journal_path)

    {gamma, room} = load_room_env(base)

    env = Map.merge(extra, %{gamma: gamma, room: room, journal: KomkiMediator.Journal})
    {:ok, _env} = KomkiMediator.Env.start_link(env)

    Map.put(env, :journal_path, journal_path)
  end

  @doc "Umgebung mit dem Referenzraum vertraulich (Connector-Vertrag §7)."
  def vertraulich(env) do
    put_in(env.room.workspace_bindings, KomkiMediator.Templates.vertraulich_bindings())
  end

  @doc """
  Kurzer Socket-Pfad unter /tmp: macOS begrenzt Unix-Socket-Pfade auf 103
  Byte, System.tmp_dir!/0 liegt dort tief unter /var/folders.
  """
  def tmp_socket do
    "/tmp/kmt-" <> Base.encode16(:crypto.strong_rand_bytes(6), case: :lower) <> ".sock"
  end

  @doc "Zufaelliges Kanal-Token (64 Hex-Zeichen, wie komki up es schreibt)."
  def new_token, do: Base.encode16(:crypto.strong_rand_bytes(32), case: :lower)

  @doc """
  Startet einen vollstaendigen Vermittler-Baum auf einem frischen Socket
  (Besitz beim Test-Supervisor: start_supervised reisst den Baum mit jedem
  Test deterministisch ab — benanntes Journal, Env, anubis-Registry, Socket).
  """
  def start_socket_server!(opts \\ []) do
    base = Keyword.get_lazy(opts, :base, &provisioned_base/0)
    {gamma, room} = load_room_env(base)
    socket = Keyword.get_lazy(opts, :socket, &tmp_socket/0)
    token = Keyword.get_lazy(opts, :token, &new_token/0)
    journal_path = Path.join([base, "mediator", "journal", "pdr.jsonl"])

    ExUnit.Callbacks.start_supervised!(
      {KomkiMediator.Supervisor, {journal_path, gamma, room, %{socket: socket, token: token}}}
    )

    %{base: base, socket: socket, token: token, journal_path: journal_path}
  end

  def stop_named(module) do
    case Process.whereis(module) do
      nil -> :ok
      _pid -> GenServer.stop(module)
    end
  end
end
