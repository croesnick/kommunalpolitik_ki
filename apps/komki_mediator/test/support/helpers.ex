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

  def stop_named(module) do
    case Process.whereis(module) do
      nil -> :ok
      _pid -> GenServer.stop(module)
    end
  end
end
