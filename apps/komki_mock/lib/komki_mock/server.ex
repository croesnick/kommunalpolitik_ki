defmodule KomkiMock.Server do
  @moduledoc """
  One running mock: the adapter's data, the current seed and scenario, two
  loopback listeners (data and control) and the files in the state
  directory.

  All requests and control commands go through this process, so they are
  serialized: two parallel requests never see a half-applied change. Every
  change of data is written atomically (temp file, then rename) before the
  reply leaves.

  State directory:

  - `state.json` — `seed`, `scenario`, `delay_ms`, `data`; survives restarts
  - `ports.json` — `data` and `control` port of this run
  - `requests.jsonl` — one line per data request; cleared by seed and reset

  Scenarios: `ok`; `error` (every request answers 500); `slow` (every reply
  waits `delay_ms`); `refused` (the data port accepts no connections).
  """

  use GenServer

  alias KomkiMock.{ControlPlug, DataPlug}

  @scenarios ~w(ok error slow refused)
  @default_delay_ms 3_000
  # How long stopping the data listener waits for open connections; a
  # handler may be blocked on a call into this very process.
  @drain_ms 100

  @type public_state :: %{String.t() => term()}

  # --- API ----------------------------------------------------------------

  @doc """
  Start a mock. Options: `:adapter` (module, required), `:dir` (state
  directory, required), `:seed` (initial seed when there is no state file
  yet, default `"default"`), `:data_port` and `:control_port` (default 0,
  i.e. any free port).
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  @spec stop(GenServer.server()) :: :ok
  def stop(server), do: GenServer.stop(server)

  @spec ports(GenServer.server()) :: %{data: :inet.port_number(), control: :inet.port_number()}
  def ports(server), do: GenServer.call(server, :ports)

  @doc false
  @spec handle_request(GenServer.server(), KomkiMock.Adapter.request()) ::
          {KomkiMock.Adapter.response(), delay_ms :: non_neg_integer()}
  def handle_request(server, request), do: GenServer.call(server, {:request, request})

  @spec seed(GenServer.server(), String.t()) :: {:ok, public_state()} | {:error, :unknown_seed}
  def seed(server, name), do: GenServer.call(server, {:seed, name})

  @spec reset(GenServer.server()) :: {:ok, public_state()}
  def reset(server), do: GenServer.call(server, :reset)

  @spec scenario(GenServer.server(), String.t(), pos_integer() | nil) ::
          {:ok, public_state()} | {:error, :unknown_scenario}
  def scenario(server, name, delay_ms \\ nil),
    do: GenServer.call(server, {:scenario, name, delay_ms})

  @spec state(GenServer.server()) :: public_state()
  def state(server), do: GenServer.call(server, :state)

  @spec log(GenServer.server()) :: [map()]
  def log(server), do: GenServer.call(server, :log)

  # --- GenServer ----------------------------------------------------------

  @impl true
  def init(opts) do
    adapter = Keyword.fetch!(opts, :adapter)
    dir = Keyword.fetch!(opts, :dir)
    File.mkdir_p!(dir)

    case load_or_seed(adapter, dir, Keyword.get(opts, :seed, "default")) do
      {:ok, persisted} -> {:ok, boot(persisted, adapter, dir, opts)}
      {:error, reason} -> {:stop, reason}
    end
  end

  defp boot(persisted, adapter, dir, opts) do
    {:ok, control} = listen(ControlPlug, Keyword.get(opts, :control_port, 0))
    {:ok, data} = listen(DataPlug, Keyword.get(opts, :data_port, 0))

    state =
      Map.merge(persisted, %{
        adapter: adapter,
        dir: dir,
        control_port: port(control),
        data_port: port(data),
        data_listener: data
      })

    write_json(Path.join(dir, "ports.json"), %{
      "data" => state.data_port,
      "control" => state.control_port
    })

    apply_listener(state)
  end

  @impl true
  def handle_call(:ports, _from, state),
    do: {:reply, %{data: state.data_port, control: state.control_port}, state}

  def handle_call({:request, request}, _from, state) do
    {{status, _, _} = response, state} = answer(request, state)
    append_log(state, request, status)
    delay = if state.scenario == "slow", do: state.delay_ms, else: 0
    {:reply, {response, delay}, state}
  end

  def handle_call({:seed, name}, _from, state) do
    case state.adapter.seed(name) do
      {:ok, data} ->
        state = restart(state, name, data)
        {:reply, {:ok, public(state)}, state}

      :error ->
        {:reply, {:error, :unknown_seed}, state}
    end
  end

  def handle_call(:reset, _from, state) do
    {:ok, data} = state.adapter.seed(state.seed)
    state = restart(state, state.seed, data)
    {:reply, {:ok, public(state)}, state}
  end

  def handle_call({:scenario, name, delay_ms}, _from, state) when name in @scenarios do
    state = %{state | scenario: name, delay_ms: delay_ms || state.delay_ms}
    persist(state)
    state = apply_listener(state)
    {:reply, {:ok, public(state)}, state}
  end

  def handle_call({:scenario, _name, _delay_ms}, _from, state),
    do: {:reply, {:error, :unknown_scenario}, state}

  def handle_call(:state, _from, state), do: {:reply, public(state), state}

  def handle_call(:log, _from, state) do
    entries =
      case File.read(log_path(state)) do
        {:ok, text} -> text |> String.split("\n", trim: true) |> Enum.map(&JSON.decode!/1)
        {:error, :enoent} -> []
      end

    {:reply, entries, state}
  end

  # --- Requests -----------------------------------------------------------

  defp answer(_request, %{scenario: "error"} = state),
    do: {{500, [{"content-type", "application/json"}], ~s({"error":"scenario error"})}, state}

  defp answer(request, state) do
    {response, data} = state.adapter.handle(request, state.data)

    if data == state.data do
      {response, state}
    else
      state = %{state | data: normalize(data)}
      persist(state)
      {response, state}
    end
  end

  defp append_log(state, request, status) do
    entry = %{
      "at" => DateTime.to_iso8601(DateTime.utc_now()),
      "method" => request.method,
      "path" => request.path,
      "query" => request.query,
      "status" => status,
      "scenario" => state.scenario
    }

    File.write!(log_path(state), [JSON.encode!(entry), "\n"], [:append])
  end

  # --- Seeds and persistence ----------------------------------------------

  defp load_or_seed(adapter, dir, seed) do
    case File.read(Path.join(dir, "state.json")) do
      {:ok, json} ->
        %{"seed" => seed, "scenario" => scenario, "delay_ms" => delay, "data" => data} =
          JSON.decode!(json)

        {:ok, %{seed: seed, scenario: scenario, delay_ms: delay, data: data}}

      {:error, :enoent} ->
        case adapter.seed(seed) do
          {:ok, data} ->
            state = fresh(seed, data)
            persist(Map.put(state, :dir, dir))
            {:ok, state}

          :error ->
            {:error, {:unknown_seed, seed}}
        end
    end
  end

  # Seed and reset: data from the seed, scenario ok, empty request log.
  defp restart(state, seed, data) do
    state = Map.merge(state, fresh(seed, data))
    persist(state)
    File.rm(log_path(state))
    apply_listener(state)
  end

  defp fresh(seed, data),
    do: %{seed: seed, scenario: "ok", delay_ms: @default_delay_ms, data: normalize(data)}

  # Data as the state file holds it, so a restart changes nothing.
  defp normalize(data), do: data |> JSON.encode!() |> JSON.decode!()

  defp persist(state) do
    write_json(Path.join(state.dir, "state.json"), public(state))
  end

  defp public(state) do
    %{
      "seed" => state.seed,
      "scenario" => state.scenario,
      "delay_ms" => state.delay_ms,
      "data" => state.data
    }
  end

  defp write_json(path, value) do
    tmp = path <> ".tmp"
    File.write!(tmp, JSON.encode!(value))
    File.rename!(tmp, path)
  end

  defp log_path(state), do: Path.join(state.dir, "requests.jsonl")

  # --- Listeners ----------------------------------------------------------

  defp listen(plug, port) do
    Bandit.start_link(
      plug: {plug, server: self()},
      ip: {127, 0, 0, 1},
      port: port,
      startup_log: false
    )
  end

  defp port(listener) do
    {:ok, {_ip, port}} = ThousandIsland.listener_info(listener)
    port
  end

  # The data listener runs unless the scenario is refused; it comes back on
  # the same port.
  defp apply_listener(%{scenario: "refused", data_listener: nil} = state), do: state

  defp apply_listener(%{scenario: "refused"} = state) do
    :ok = ThousandIsland.stop(state.data_listener, @drain_ms)
    %{state | data_listener: nil}
  end

  defp apply_listener(%{data_listener: nil} = state) do
    {:ok, listener} = listen(DataPlug, state.data_port)
    %{state | data_listener: listener}
  end

  defp apply_listener(state), do: state
end
