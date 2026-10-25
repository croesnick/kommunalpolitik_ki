defmodule KomkiCli.Hangup do
  @moduledoc """
  pi endet mit seiner Session (Ticket #174).

  `session-chain` startet pi als Port-Kind. erl_child_setup macht jedes
  Port-Kind zum eigenen Sitzungsleiter (`setsid`), deshalb erreicht das
  SIGHUP eines geschlossenen tmux-Fensters nur den BEAM, nicht pi. Ohne
  diesen Handler starb der BEAM, und pi lief ohne Terminal weiter, samt
  seinem komki-relay.js.

  Der Handler haengt sich an den Signal-Server des BEAM: Bei SIGHUP oder
  SIGTERM beendet er pi (TERM, nach einer Sekunde KILL) und haelt dann den
  BEAM an.
  """

  @behaviour :gen_event

  @signals [:sighup, :sigterm]
  @grace_ms 1_000

  @doc "pi (`os_pid`) bei SIGHUP/SIGTERM mitbeenden."
  @spec install(pos_integer()) :: :ok
  def install(os_pid) when is_integer(os_pid) and os_pid > 0 do
    :ok = :gen_event.add_handler(:erl_signal_server, __MODULE__, os_pid)
    Enum.each(@signals, &:os.set_signal(&1, :handle))
  end

  @doc "pi beenden: TERM, nach der Schonfrist KILL, falls es noch lebt."
  @spec stop_pi(pos_integer(), non_neg_integer()) :: :ok
  def stop_pi(os_pid, grace_ms \\ @grace_ms) do
    signal(os_pid, "TERM")
    Process.sleep(grace_ms)
    if alive?(os_pid), do: signal(os_pid, "KILL")
    :ok
  end

  @doc """
  Fallback fuer `komki down`: pi-Prozesse dieser Instanz, die ihre Session
  ueberlebt haben, samt Relay beenden. Erkannt an einem komki-relay.js mit
  dem Pfad dieser Instanz, dessen pi verwaist ist (Elternprozess 1) oder
  der selbst verwaist ist. Laufende Sessions bleiben unberuehrt. Liefert
  die Zahl der beendeten pi-Prozesse.
  """
  @spec reap_orphans(String.t()) :: non_neg_integer()
  def reap_orphans(relay_path) do
    {out, _code} = System.cmd("/usr/bin/pgrep", ["-f", relay_path], stderr_to_stdout: true)

    out
    |> String.split()
    |> Enum.flat_map(&parse_pid/1)
    |> Enum.map(&reap_relay/1)
    |> Enum.sum()
  end

  defp reap_relay(relay_pid) do
    parent = ppid(relay_pid)

    cond do
      parent == 1 ->
        signal(relay_pid, "TERM")
        0

      is_integer(parent) and ppid(parent) == 1 ->
        stop_pi(parent)
        if alive?(relay_pid), do: signal(relay_pid, "TERM")
        1

      true ->
        0
    end
  end

  defp ppid(pid) do
    case System.cmd("/bin/ps", ["-o", "ppid=", "-p", Integer.to_string(pid)],
           stderr_to_stdout: true
         ) do
      {out, 0} -> out |> String.trim() |> parse_pid() |> List.first()
      _ -> nil
    end
  end

  defp parse_pid(text) do
    case Integer.parse(text) do
      {pid, ""} -> [pid]
      _ -> []
    end
  end

  @impl :gen_event
  def init(os_pid), do: {:ok, os_pid}

  @impl :gen_event
  def handle_event(signal, os_pid) when signal in @signals do
    stop_pi(os_pid)
    System.halt(128 + signal_number(signal))
  end

  def handle_event(_event, os_pid), do: {:ok, os_pid}

  @impl :gen_event
  def handle_call(_request, os_pid), do: {:ok, :ok, os_pid}

  defp signal(os_pid, name),
    do: System.cmd("/bin/kill", ["-" <> name, Integer.to_string(os_pid)], stderr_to_stdout: true)

  defp alive?(os_pid) do
    {_out, code} =
      System.cmd("/bin/kill", ["-0", Integer.to_string(os_pid)], stderr_to_stdout: true)

    code == 0
  end

  defp signal_number(:sighup), do: 1
  defp signal_number(:sigterm), do: 15
end
