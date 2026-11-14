# Minimal Chrome DevTools Protocol client over --remote-debugging-pipe
# (#510): the browser reads NUL-terminated JSON messages on fd 3 and writes
# them on fd 4. The launcher maps both onto the stdin and stdout of an
# Erlang port, so no WebSocket client and no listening debug port is needed.

defmodule Screenshot.CDP do
  @moduledoc false

  defstruct [:port, buf: "", id: 0, events: []]

  @max_events 200

  def new(port), do: %__MODULE__{port: port}

  @doc "Sends a command and waits for its reply: `{:ok, result, cdp}` or `{:error, message, cdp}`."
  def call(cdp, method, params \\ %{}, session \\ nil, timeout \\ 30_000) do
    id = cdp.id + 1
    msg = %{"id" => id, "method" => method, "params" => params}
    msg = if session, do: Map.put(msg, "sessionId", session), else: msg
    Port.command(cdp.port, [JSON.encode!(msg), 0])

    await(%{cdp | id: id}, &match?(%{"id" => ^id}, &1), deadline(timeout), method)
    |> case do
      {:ok, %{"error" => %{"message" => m}}, cdp} -> {:error, "#{method}: #{m}", cdp}
      {:ok, %{"result" => result}, cdp} -> {:ok, result, cdp}
      {:error, _, _} = error -> error
    end
  end

  @doc "Like `call/5`, raises on an error reply."
  def call!(cdp, method, params \\ %{}, session \\ nil, timeout \\ 30_000) do
    case call(cdp, method, params, session, timeout) do
      {:ok, result, cdp} -> {result, cdp}
      {:error, message, _} -> raise message
    end
  end

  @doc "Waits for an event of `method` (for `session`), including events already buffered."
  def await_event(cdp, method, session, timeout \\ 30_000) do
    match = &match?(%{"method" => ^method, "sessionId" => ^session}, &1)

    case Enum.split_with(cdp.events, match) do
      {[event | _], rest} ->
        {:ok, event["params"], %{cdp | events: rest}}

      {[], _} ->
        case await(cdp, match, deadline(timeout), method) do
          {:ok, event, cdp} -> {:ok, event["params"], cdp}
          error -> error
        end
    end
  end

  @doc "Drops buffered events (before a step whose events matter)."
  def flush(cdp), do: %{cdp | events: []}

  @doc "Evaluates a JavaScript expression in the page and returns its value."
  def eval!(cdp, session, expression) do
    {result, cdp} =
      call!(
        cdp,
        "Runtime.evaluate",
        %{"expression" => expression, "returnByValue" => true, "awaitPromise" => true},
        session
      )

    case result do
      %{"exceptionDetails" => details} -> raise "JavaScript: #{inspect(details["text"])}"
      %{"result" => r} -> {r["value"], cdp}
    end
  end

  defp deadline(timeout), do: System.monotonic_time(:millisecond) + timeout

  # Reads messages until `match` hits; everything else without an id is an
  # event and stays buffered for await_event/4.
  defp await(cdp, match, deadline, what) do
    case next_message(cdp) do
      {:ok, msg, cdp} ->
        cond do
          match.(msg) -> {:ok, msg, cdp}
          Map.has_key?(msg, "id") -> await(cdp, match, deadline, what)
          true -> await(buffer_event(cdp, msg), match, deadline, what)
        end

      :more ->
        left = deadline - System.monotonic_time(:millisecond)
        port = cdp.port

        receive do
          {^port, {:data, data}} ->
            await(%{cdp | buf: cdp.buf <> data}, match, deadline, what)

          {^port, {:exit_status, status}} ->
            {:error, "Browser beendet (Status #{status}) während #{what}", cdp}
        after
          max(left, 0) -> {:error, "Zeitlimit bei #{what}", cdp}
        end
    end
  end

  defp next_message(cdp) do
    case :binary.split(cdp.buf, <<0>>) do
      [msg, rest] -> {:ok, JSON.decode!(msg), %{cdp | buf: rest}}
      [_] -> :more
    end
  end

  defp buffer_event(cdp, msg),
    do: %{cdp | events: Enum.take(cdp.events ++ [msg], -@max_events)}
end
