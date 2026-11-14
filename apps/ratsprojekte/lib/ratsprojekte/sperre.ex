defmodule Ratsprojekte.Sperre do
  @moduledoc """
  The lock of the hub (ADR 0004 „Lokal, ohne Konten“). The release starts
  locked: no key, no open database. `oeffnen/1` opens the sealed key (Touch
  ID through `komki-tresor`), starts the repo with it and hands out a
  one-time link, which the web layer trades for a session cookie
  (`einloesen/2`). Every further `oeffnen/1` asks for Touch ID again, so a
  process in the user account gets no link without the person at the Mac.

  After `:sperre_nach` milliseconds without an action in the interface
  (`handlung/1`) the hub locks again: the repo stops, the session marker is
  dropped, open LiveViews receive `:gesperrt` on the topic `"sperre"`.
  Connector calls do not count as actions, otherwise an agent could keep
  the hub open indefinitely.

  Before a schema change on an existing database the hub copies it next to
  itself (`Ort.kopie/1`); only the latest copy is kept. The copy is
  ciphertext like the original.

  Options: `:home`, `:provider` (`SealedEnvelope` provider), `:sperre_nach`,
  `:repo`, `:repo_supervisor`, `:migrationen` (path), `:pubsub`, `:name`.
  """

  use GenServer

  require Logger

  alias Ratsprojekte.{Ort, Schluessel}

  @link_gueltig_ms 120_000
  @topic "sperre"

  # -- client -----------------------------------------------------------------

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    # `name: nil` starts an unregistered lock (tests).
    case Keyword.get(opts, :name, __MODULE__) do
      nil -> GenServer.start_link(__MODULE__, opts)
      name -> GenServer.start_link(__MODULE__, opts, name: name)
    end
  end

  @doc """
  Open the sealed key (Touch ID) in the calling process, unlock with it and
  return a one-time link token. The key itself never enters this server's
  state; only its hash, to compare later unlocks.
  """
  @spec oeffnen(GenServer.server()) ::
          {:ok, String.t()} | {:error, Schluessel.error() | :datenbank}
  def oeffnen(server \\ __MODULE__) do
    %{home: home, provider: provider} = GenServer.call(server, :einstellungen)

    with {:ok, key} <- Schluessel.oeffnen(home, provider) do
      GenServer.call(server, {:entsperren, key}, 60_000)
    end
  end

  @doc "Lock now."
  @spec sperren(GenServer.server()) :: :ok
  def sperren(server \\ __MODULE__), do: GenServer.call(server, :sperren)

  @spec status(GenServer.server()) :: :offen | :gesperrt
  def status(server \\ __MODULE__), do: GenServer.call(server, :status)

  @doc "Trade a one-time link token for the session marker of this unlock."
  @spec einloesen(GenServer.server(), String.t()) :: {:ok, String.t()} | :error
  def einloesen(server \\ __MODULE__, token), do: GenServer.call(server, {:einloesen, token})

  @doc "Is `marker` the session marker of the current unlock?"
  @spec zugang?(GenServer.server(), term()) :: boolean()
  def zugang?(server \\ __MODULE__, marker), do: GenServer.call(server, {:zugang?, marker})

  @doc "An action in the interface; postpones the lock."
  @spec handlung(GenServer.server()) :: :ok
  def handlung(server \\ __MODULE__), do: GenServer.cast(server, :handlung)

  @doc "PubSub topic on which `:gesperrt` is broadcast."
  @spec topic() :: String.t()
  def topic, do: @topic

  # -- server -----------------------------------------------------------------

  @impl true
  def init(opts) do
    repo = Keyword.get(opts, :repo, Ratsprojekte.Repo)

    state = %{
      home: Keyword.fetch!(opts, :home),
      provider: Keyword.fetch!(opts, :provider),
      sperre_nach: Keyword.fetch!(opts, :sperre_nach),
      repo: repo,
      repo_supervisor: Keyword.get(opts, :repo_supervisor, Ratsprojekte.RepoSupervisor),
      migrationen:
        Keyword.get_lazy(opts, :migrationen, fn -> Ecto.Migrator.migrations_path(repo) end),
      pubsub: Keyword.get(opts, :pubsub, Ratsprojekte.PubSub)
    }

    # Fail closed after a restart of this server: a repo left running from
    # before would be open without a lock that knows about it.
    repo_stoppen(state)
    {:ok, gesperrt(state)}
  end

  @impl true
  def handle_call(:einstellungen, _from, state),
    do: {:reply, Map.take(state, [:home, :provider]), state}

  def handle_call({:entsperren, key}, _from, %{status: :offen} = state) do
    if Plug.Crypto.secure_compare(hash(key), state.key_hash),
      do: link(state),
      else: {:reply, {:error, :falscher_schluessel}, state}
  end

  def handle_call({:entsperren, key}, _from, state) do
    db = Ort.datenbank(state.home)
    neu? = not File.exists?(db)

    with :ok <- Schluessel.pruefen(key, db),
         :ok <- if(neu?, do: anlegen(db, key), else: :ok),
         {:ok, _pid} <- repo_starten(state, db, key),
         :ok <- migrieren(state, neu?) do
      state
      |> Map.merge(%{status: :offen, key_hash: hash(key), marker: zufall(), letzte: jetzt()})
      |> planen(state.sperre_nach)
      |> link()
    else
      {:error, :falscher_schluessel} = error ->
        {:reply, error, state}

      _other ->
        repo_stoppen(state)
        {:reply, {:error, :datenbank}, state}
    end
  end

  def handle_call(:sperren, _from, state), do: {:reply, :ok, sperren_jetzt(state)}

  def handle_call(:status, _from, state), do: {:reply, state.status, state}

  def handle_call({:einloesen, token}, _from, state) do
    {deadline, links} = Map.pop(state.links, hash(token))

    reply =
      if state.status == :offen and is_integer(deadline) and deadline >= jetzt(),
        do: {:ok, state.marker},
        else: :error

    {:reply, reply, %{state | links: links}}
  end

  def handle_call({:zugang?, marker}, _from, state) do
    ok? =
      state.status == :offen and is_binary(marker) and
        Plug.Crypto.secure_compare(marker, state.marker)

    {:reply, ok?, state}
  end

  @impl true
  def handle_cast(:handlung, %{status: :offen} = state),
    do: {:noreply, %{state | letzte: jetzt()}}

  def handle_cast(:handlung, state), do: {:noreply, state}

  @impl true
  def handle_info({:pruefen, ref}, %{timer: ref} = state) do
    rest = state.sperre_nach - (jetzt() - state.letzte)
    {:noreply, if(rest <= 0, do: sperren_jetzt(state), else: planen(state, rest))}
  end

  # A timer from an earlier unlock.
  def handle_info({:pruefen, _stale}, state), do: {:noreply, state}

  # -- internals --------------------------------------------------------------

  defp gesperrt(state),
    do:
      Map.merge(state, %{
        status: :gesperrt,
        key_hash: nil,
        marker: nil,
        links: %{},
        letzte: nil,
        timer: nil
      })

  defp sperren_jetzt(state) do
    repo_stoppen(state)
    Phoenix.PubSub.broadcast(state.pubsub, @topic, :gesperrt)
    gesperrt(state)
  end

  defp link(state) do
    token = zufall()
    jetzt = jetzt()
    links = for {h, d} <- state.links, d >= jetzt, into: %{}, do: {h, d}

    {:reply, {:ok, token},
     %{state | links: Map.put(links, hash(token), jetzt + @link_gueltig_ms)}}
  end

  defp planen(state, ms) do
    ref = make_ref()
    Process.send_after(self(), {:pruefen, ref}, ms)
    %{state | timer: ref}
  end

  # Create a new database with one connection and switch it to WAL; the
  # pool's connections would otherwise race for that switch and fail with
  # "database is locked" while the first migration runs.
  defp anlegen(db, key) do
    {:ok, conn} = Exqlite.Sqlite3.open(db)

    try do
      with :ok <- Exqlite.Sqlite3.execute(conn, "PRAGMA key = " <> Schluessel.pragma(key)),
           :ok <- Exqlite.Sqlite3.execute(conn, "PRAGMA journal_mode = WAL") do
        File.chmod(db, 0o600)
      end
    after
      Exqlite.Sqlite3.close(conn)
    end
  end

  defp repo_starten(state, db, key) do
    DynamicSupervisor.start_child(
      state.repo_supervisor,
      {state.repo, database: db, key: Schluessel.pragma(key)}
    )
  end

  defp repo_stoppen(state) do
    for {_, pid, _, _} <- DynamicSupervisor.which_children(state.repo_supervisor), is_pid(pid) do
      DynamicSupervisor.terminate_child(state.repo_supervisor, pid)
    end

    :ok
  end

  defp migrieren(state, neu?) do
    offen? =
      state.repo
      |> Ecto.Migrator.migrations([state.migrationen])
      |> Enum.any?(&match?({:down, _, _}, &1))

    if offen? do
      unless neu?, do: kopieren(state)
      Ecto.Migrator.run(state.repo, [state.migrationen], :up, all: true, log: false)
    end

    :ok
  rescue
    error ->
      # The marker for Ratsprojekte.Logfilter, not printed metadata.
      # credo:disable-for-next-line Credo.Check.Warning.MissedMetadataKeyInLoggerConfig
      Logger.warning("Migration fehlgeschlagen (#{inspect(error.__struct__)})", inhaltsfrei: true)
      {:error, :datenbank}
  end

  # Checkpoint first, so the main file holds everything, then copy it; the
  # rename replaces the previous copy in one step.
  defp kopieren(state) do
    state.repo.query!("PRAGMA wal_checkpoint(TRUNCATE)")
    kopie = Ort.kopie(state.home)
    File.cp!(Ort.datenbank(state.home), kopie <> ".tmp")
    File.chmod!(kopie <> ".tmp", 0o600)
    File.rename!(kopie <> ".tmp", kopie)
  end

  defp hash(value), do: :crypto.hash(:sha256, value)
  defp zufall, do: 32 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
  defp jetzt, do: System.monotonic_time(:millisecond)
end
