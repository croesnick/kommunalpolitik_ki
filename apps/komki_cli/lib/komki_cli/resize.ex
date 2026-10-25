defmodule KomkiCli.Resize do
  @moduledoc """
  pi zeichnet nach einem Terminal-Resize neu (Ticket #197).

  `session-chain` startet pi als Port-Kind. erl_child_setup macht jedes
  Port-Kind zum eigenen Sitzungsleiter (`setsid`), pi hat damit kein
  Steuerterminal. Das SIGWINCH einer vergroesserten oder verkleinerten
  tmux-Pane erreicht deshalb nur den BEAM (Vordergrund-Gruppe des
  Pane-PTY), nicht pi — node feuert kein `resize`, pi rendert mit der
  alten Breite weiter. Die neue Groesse liest pi ueber den Pane-PTY auf
  fd 0/1 auch ohne Steuerterminal; es fehlt nur das Signal.

  Der Handler haengt sich an den Signal-Server des BEAM und reicht
  SIGWINCH an pi weiter. Anders als `KomkiCli.Hangup` laeuft der BEAM
  danach weiter.
  """

  @behaviour :gen_event

  @doc "SIGWINCH an pi (`os_pid`) weiterreichen."
  @spec install(pos_integer()) :: :ok
  def install(os_pid) when is_integer(os_pid) and os_pid > 0 do
    :ok = :gen_event.add_handler(:erl_signal_server, __MODULE__, os_pid)
    :os.set_signal(:sigwinch, :handle)
  end

  @impl :gen_event
  def init(os_pid), do: {:ok, os_pid}

  @impl :gen_event
  def handle_event(:sigwinch, os_pid) do
    System.cmd("/bin/kill", ["-WINCH", Integer.to_string(os_pid)], stderr_to_stdout: true)
    {:ok, os_pid}
  end

  def handle_event(_event, os_pid), do: {:ok, os_pid}

  @impl :gen_event
  def handle_call(_request, os_pid), do: {:ok, :ok, os_pid}
end
