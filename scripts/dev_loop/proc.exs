# Runs an external program with a wall-clock limit and streams its output
# into a log file line by line, so a herdr pane can `tail -f` it. System.cmd
# has neither a timeout nor streaming, hence the port.

defmodule DevLoop.Proc do
  @moduledoc false

  @doc """
  Returns `{:ok, lines}`, `{:error, status, lines}`, `{:timeout, lines}` or
  `{:cancelled, lines}`; `lines` are the last #{200} output lines. Options:
  `:cd`, `:env` (`{name, value | false}`), `:timeout_ms`, `:log` (file
  path), `:cancel` (checked every second; when it returns true the program
  is ended).
  """
  def run(cmd, args, opts) do
    exe = System.find_executable(cmd) || raise "#{cmd} nicht gefunden"
    log = File.open!(Keyword.fetch!(opts, :log), [:append, :utf8])

    # A port keeps the child's stdin open, and `claude -p` waits for input on
    # it before it starts. The shell hands the program /dev/null instead and
    # execs it, so the port's OS pid stays the program's pid (kill/1).
    port =
      Port.open({:spawn_executable, "/bin/sh"}, [
        :binary,
        :exit_status,
        :stderr_to_stdout,
        {:line, 10_000_000},
        args: ["-c", ~S(exec "$0" "$@" < /dev/null), exe | args],
        cd: Keyword.get(opts, :cd, File.cwd!()),
        env: for({k, v} <- Keyword.get(opts, :env, []), do: {~c"#{k}", v && ~c"#{v}"})
      ])

    deadline = System.monotonic_time(:millisecond) + Keyword.fetch!(opts, :timeout_ms)
    # A tick every second checks deadline and cancel, also while output
    # keeps streaming in.
    tick = make_ref()
    {:ok, timer} = :timer.send_interval(1000, {tick, :tick})

    try do
      collect(port, log, {tick, deadline, Keyword.get(opts, :cancel, fn -> false end)}, [], "")
    after
      :timer.cancel(timer)
      flush(tick)
      File.close(log)
    end
  end

  defp collect(port, log, {tick, deadline, cancel} = limits, tail, partial) do
    receive do
      {^port, {:data, {:noeol, chunk}}} ->
        collect(port, log, limits, tail, partial <> chunk)

      {^port, {:data, {:eol, chunk}}} ->
        line = partial <> chunk
        IO.write(log, line <> "\n")
        collect(port, log, limits, Enum.take([line | tail], 200), "")

      {^port, {:exit_status, 0}} ->
        {:ok, Enum.reverse(tail)}

      {^port, {:exit_status, status}} ->
        {:error, status, Enum.reverse(tail)}

      {^tick, :tick} ->
        cond do
          System.monotonic_time(:millisecond) >= deadline ->
            kill(port)
            {:timeout, Enum.reverse(tail)}

          cancel.() ->
            kill(port)
            {:cancelled, Enum.reverse(tail)}

          true ->
            collect(port, log, limits, tail, partial)
        end
    end
  end

  defp flush(tick) do
    receive do
      {^tick, :tick} -> flush(tick)
    after
      0 -> :ok
    end
  end

  # Children first (mix, beam, shells the agent started), then the process.
  defp kill(port) do
    case Port.info(port, :os_pid) do
      {:os_pid, pid} ->
        System.cmd("pkill", ["-TERM", "-P", "#{pid}"])
        System.cmd("kill", ["-TERM", "#{pid}"])

      nil ->
        :ok
    end

    Port.close(port)
  catch
    _, _ -> :ok
  end
end
