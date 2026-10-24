defmodule KomkiCli.Keychain do
  @moduledoc """
  Credentials aus dem macOS-Schluesselbund (Ticket #146, CONTRACT.md §4/§5):
  `security find-generic-password -s <service> -w` mit Timeout.

  Der Wert verlaesst dieses Modul nur als Rueckgabe an den Aufrufer, der
  ihn als stdin-JSON-Zeile an genau seinen Connector schreibt. Er steht nie
  in argv, Umgebung, Log, Status oder Fehlermeldungen: Fehler tragen nur
  den Service-Namen und eine Ursache, nie stdout oder stderr von
  `security`.

  `opts[:command]` (oder die Application-Env `:komki_cli, :security`, die
  `test_helper.exs` auf ein Fake-Kommando setzt) ersetzt
  `/usr/bin/security`: Tests rufen `security` nie fuer echte Eintraege auf.
  """

  @security "/usr/bin/security"
  @timeout_ms 5_000
  # security(1): Exit 44 = errSecItemNotFound
  @not_found 44

  @type error :: :missing | :timeout | {:failed, integer()}

  @doc "Wert eines generischen Passworts lesen."
  @spec fetch(String.t(), keyword()) :: {:ok, String.t()} | {:error, error()}
  def fetch(service, opts \\ []) when is_binary(service) do
    case run(["find-generic-password", "-s", service, "-w"], opts) do
      {:ok, out} ->
        case String.trim_trailing(out, "\n") do
          "" -> {:error, :missing}
          value -> {:ok, value}
        end

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Nur die Existenz pruefen (ohne `-w`: kein Wert, keine Zugriffsrueckfrage
  des Schluesselbunds). Fuer den Doctor.
  """
  @spec present(String.t(), keyword()) :: :ok | {:error, error()}
  def present(service, opts \\ []) when is_binary(service) do
    case run(["find-generic-password", "-s", service], opts) do
      {:ok, _attributes} -> :ok
      {:error, _} = error -> error
    end
  end

  @doc "Fehler als Text ohne Wert (fuer Doctor und Logs)."
  @spec describe(String.t(), error()) :: String.t()
  def describe(service, :missing), do: "Schluesselbund-Eintrag '" <> service <> "' fehlt"

  def describe(service, :timeout),
    do: "Schluesselbund-Abfrage '" <> service <> "' nach Timeout abgebrochen"

  def describe(service, {:failed, code}),
    do:
      "Schluesselbund-Abfrage '" <> service <> "' fehlgeschlagen (exit " <> to_string(code) <> ")"

  # Port statt System.cmd: nur so laesst sich ein haengendes `security`
  # nach dem Timeout beenden. stderr wird verworfen (nie in Meldungen).
  defp run(args, opts) do
    command = Keyword.get(opts, :command, Application.get_env(:komki_cli, :security, @security))
    timeout = Keyword.get(opts, :timeout, @timeout_ms)

    port =
      Port.open({:spawn_executable, "/bin/sh"}, [
        :binary,
        :exit_status,
        :use_stdio,
        args: ["-c", "exec \"$0\" \"$@\" 2>/dev/null </dev/null", command | args]
      ])

    collect(port, [], System.monotonic_time(:millisecond) + timeout)
  end

  defp collect(port, acc, deadline) do
    left = max(deadline - System.monotonic_time(:millisecond), 0)

    receive do
      {^port, {:data, data}} -> collect(port, [acc, data], deadline)
      {^port, {:exit_status, 0}} -> {:ok, IO.iodata_to_binary(acc)}
      {^port, {:exit_status, @not_found}} -> {:error, :missing}
      {^port, {:exit_status, code}} -> {:error, {:failed, code}}
    after
      left -> kill(port)
    end
  end

  defp kill(port) do
    case Port.info(port, :os_pid) do
      {:os_pid, pid} -> System.cmd("/bin/kill", ["-KILL", to_string(pid)])
      nil -> :ok
    end

    Port.close(port)
    {:error, :timeout}
  catch
    :error, :badarg -> {:error, :timeout}
  end
end
