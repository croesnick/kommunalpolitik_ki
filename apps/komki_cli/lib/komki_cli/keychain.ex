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

  @type error :: :missing | :timeout | :invalid | :not_stored | {:failed, integer()}

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

  @doc """
  Wert als generisches Passwort ablegen oder ersetzen (`komki secret set`,
  heute nur Siegel aus `KomkiCli.Tresor`). Der Wert steht nie in argv (dort
  saehe ihn jeder Prozess per `ps`). `add-generic-password -w` ohne Wert
  liest ihn ueber eine Passwortabfrage und kuerzt ihn dabei auf 128 Byte;
  ein Siegel ist laenger. Deshalb geht der ganze Befehl als eine Zeile an
  `security -i` (Befehle von stdin). Weil `security -i` die Zeile selbst
  zerlegt, sind fuer Service, Account und Wert nur Zeichen ohne
  Sonderbedeutung erlaubt. Danach liest komki den Eintrag zurueck und
  vergleicht: Ein gekuerzter oder fremder Wert ist ein Fehler.
  """
  @spec store(String.t(), String.t(), keyword()) :: :ok | {:error, error()}
  def store(service, value, opts \\ []) when is_binary(service) and is_binary(value) do
    # `-U` ersetzt nur bei gleichem Service UND Account. Ein vorhandener
    # Eintrag (etwa von Hand unter anderem Account angelegt) behaelt seinen
    # Account, sonst entstuende ein zweiter Eintrag neben dem alten.
    account =
      Keyword.get_lazy(opts, :account, fn ->
        existing_account(service, opts) || System.get_env("USER") || "komki"
      end)

    with :ok <- plain_words([service, account, value]),
         {:ok, _} <- interactive(service, account, value, opts) do
      verify_stored(service, value, opts)
    end
  end

  @word ~r/\A[A-Za-z0-9@._+\/=-]+\z/

  defp plain_words(words) do
    if Enum.all?(words, &(&1 =~ @word)), do: :ok, else: {:error, :invalid}
  end

  # `head -n 1` beendet stdin nach der einen Zeile; `security -i` endet dann.
  defp interactive(service, account, value, opts) do
    command = Keyword.get(opts, :command, Application.get_env(:komki_cli, :security, @security))

    port =
      Port.open({:spawn_executable, "/bin/sh"}, [
        :binary,
        :exit_status,
        :use_stdio,
        args: ["-c", "head -n 1 | exec \"$0\" -i >/dev/null 2>&1", command]
      ])

    line =
      Enum.join(["add-generic-password", "-s", service, "-a", account, "-U", "-w", value], " ")

    Port.command(port, line <> "\n")
    collect(port, [], System.monotonic_time(:millisecond) + @timeout_ms)
  end

  defp verify_stored(service, value, opts) do
    case fetch(service, opts) do
      {:ok, ^value} -> :ok
      {:ok, _other} -> {:error, :not_stored}
      {:error, _} = error -> error
    end
  end

  @doc """
  Account des vorhandenen Eintrags zu `service` (aus den Attributen, ohne
  den Wert zu lesen); nil, wenn es keinen gibt.
  """
  @spec existing_account(String.t(), keyword()) :: String.t() | nil
  def existing_account(service, opts \\ []) do
    with {:ok, attributes} <- run(["find-generic-password", "-s", service], opts),
         [_, account] <- Regex.run(~r/"acct"<blob>="([^"]*)"/, attributes) do
      account
    else
      _ -> nil
    end
  end

  @doc "Fehler als Text ohne Wert (für Doctor und Logs)."
  @spec describe(String.t(), error()) :: String.t()
  def describe(service, :missing), do: "Schlüsselbund-Eintrag '" <> service <> "' fehlt"

  def describe(service, :timeout),
    do: "Schlüsselbund-Abfrage '" <> service <> "' nach Timeout abgebrochen"

  def describe(service, :invalid),
    do: "Wert für '" <> service <> "' ist leer oder enthält unzulässige Zeichen"

  def describe(service, :not_stored),
    do: "Schlüsselbund-Eintrag '" <> service <> "' enthält nach dem Schreiben einen anderen Wert"

  def describe(service, {:failed, code}),
    do:
      "Schlüsselbund-Abfrage '" <> service <> "' fehlgeschlagen (exit " <> to_string(code) <> ")"

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
