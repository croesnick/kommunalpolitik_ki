defmodule Ratsprojekte.Prompt do
  @moduledoc """
  Terminal input for the `ratsprojekte` command (Ticket #492, audit #467
  F23): `secret/2` reads the recovery code with the echo suppressed — the
  code is the database's master key and must not land in the terminal's
  echo stream (scrollback, screen sharing, recordings).

  `:io.get_password/0` is unavailable in a VM without a shell, and port
  children have no controlling terminal of their own (`/dev/tty` gives
  ENXIO). `stty -echo` therefore runs over a port with `:nouse_stdio`:
  the child inherits fd 0 of the emulator, the terminal of the person,
  and switches the echo off there. Without a terminal on stdin the input
  is refused instead of reading the key with echo on.

  This mirrors `KomkiCli.Prompt.secret/1` without depending on komki
  (Unix principle, AGENTS.md §2); `stty` is replaceable for tests.
  """

  @typedoc "Runner over fd 0: stty argument to exit status."
  @type stty :: (String.t() -> non_neg_integer())

  @doc """
  Reads a line with the echo suppressed and restores the echo after the
  read in every case. Returns `{:error, :no_tty}` without reading when
  stdin is not a terminal, `{:error, :empty}` for an empty line.
  """
  @spec secret(String.t(), stty()) :: {:ok, String.t()} | {:error, :no_tty | :empty}
  def secret(question, stty \\ &stty/1) do
    if stty.("-echo") == 0 do
      try do
        IO.write(question)
        value = IO.gets("")
        IO.write("\n")
        trimmed = if is_binary(value), do: String.trim(value), else: ""
        if trimmed == "", do: {:error, :empty}, else: {:ok, trimmed}
      after
        stty.("echo")
      end
    else
      {:error, :no_tty}
    end
  end

  # The port child inherits fd 0 of the emulator (`:nouse_stdio`), so stty
  # acts on the person's terminal; a non-terminal stdin makes stty fail.
  defp stty(arg) do
    port = Port.open({:spawn_executable, "/bin/stty"}, [:nouse_stdio, :exit_status, args: [arg]])

    receive do
      {^port, {:exit_status, code}} -> code
    after
      5_000 -> 1
    end
  end
end
