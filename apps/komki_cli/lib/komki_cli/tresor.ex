defmodule KomkiCli.Tresor do
  @moduledoc """
  Geheimnisse mit der Secure Enclave versiegeln und oeffnen, ueber das
  Hilfsprogramm `komki-tresor` (Quelle `native/komki-tresor/main.swift`).

  Der Schluesselbund enthaelt danach nur noch das Siegel. Oeffnen geht nur
  ueber die Secure Enclave dieses Macs und nur mit Touch ID oder dem
  Passwort des Macs. Das gilt fuer jeden Prozess, der den Eintrag liest,
  nicht nur fuer komki. Erlang erreicht die Secure Enclave nicht selbst,
  deshalb das eigene Programm (AGENTS.md, Elixir-first, Ausnahme).

  Klartext geht nur ueber stdin hinein und stdout heraus, nie ueber argv,
  Umgebung oder Log. `opts[:command]` (oder die Application-Env
  `:komki_cli, :tresor`) ersetzt das Programm in Tests.
  """

  @prefix "ktv1."
  @seal_timeout_ms 10_000
  # Oeffnen wartet auf Touch ID oder Passwort.
  @open_timeout_ms 120_000

  @type error ::
          :missing_bin | :no_enclave | :refused | :invalid | :timeout | {:failed, integer()}

  @doc "Ist `text` ein Siegel (und kein Klartext)?"
  @spec sealed?(String.t()) :: boolean()
  def sealed?(text), do: String.starts_with?(text, @prefix)

  @doc """
  `komki-tresor` neben dem laufenden komki (Homebrew: `libexec`, Quellbaum:
  `apps/komki_cli`), sonst im PATH. nil, wenn es fehlt. Die Application-Env
  `:komki_cli, :tresor` gewinnt (Tests).
  """
  @spec binary() :: String.t() | nil
  def binary do
    Application.get_env(:komki_cli, :tresor) || discover()
  end

  defp discover do
    beside =
      case KomkiCli.Config.self_komki() do
        nil -> nil
        komki -> Path.join(Path.dirname(komki), "komki-tresor")
      end

    cond do
      beside && File.exists?(beside) -> beside
      path = System.find_executable("komki-tresor") -> KomkiCli.Config.canonical(path)
      true -> nil
    end
  end

  @doc "Klartext versiegeln. Keine Rueckfrage: Versiegeln braucht nur den oeffentlichen Schluessel."
  @spec seal(String.t(), keyword()) :: {:ok, String.t()} | {:error, error()}
  def seal(value, opts \\ []) when is_binary(value) do
    with :ok <- one_line(value),
         {:ok, out} <- run(["seal"], value, Keyword.get(opts, :timeout, @seal_timeout_ms), opts) do
      if sealed?(out), do: {:ok, out}, else: {:error, :invalid}
    end
  end

  defp one_line(value) do
    if value == "" or String.contains?(value, ["\n", "\r"]), do: {:error, :invalid}, else: :ok
  end

  @doc "Siegel oeffnen; macOS fragt mit `reason` nach Touch ID oder Passwort."
  @spec open(String.t(), String.t(), keyword()) :: {:ok, String.t()} | {:error, error()}
  def open(sealed, reason, opts \\ []) when is_binary(sealed) and is_binary(reason) do
    if sealed?(sealed) and not String.contains?(sealed, "\n") do
      run(
        ["open", "--reason", reason],
        sealed,
        Keyword.get(opts, :timeout, @open_timeout_ms),
        opts
      )
    else
      {:error, :invalid}
    end
  end

  @doc "Fehler als Text ohne Wert."
  @spec describe(error()) :: String.t()
  def describe(:missing_bin), do: "komki-tresor nicht gefunden (Installation prüfen)"
  def describe(:no_enclave), do: "dieser Mac hat keine Secure Enclave"
  def describe(:refused), do: "Freigabe per Touch ID oder Passwort verweigert oder abgebrochen"
  def describe(:invalid), do: "Siegel ungültig oder von einem anderen Mac"
  def describe(:timeout), do: "keine Freigabe innerhalb von zwei Minuten"

  def describe({:failed, code}),
    do: "komki-tresor fehlgeschlagen (exit " <> to_string(code) <> ")"

  defp run(args, input, timeout, opts) do
    case Keyword.get_lazy(opts, :command, &binary/0) do
      nil -> {:error, :missing_bin}
      command -> spawn(command, args, input, timeout)
    end
  end

  # stderr des Programms bleibt im Terminal (Meldungen ohne Werte); stdout
  # traegt genau eine Zeile.
  defp spawn(command, args, input, timeout) do
    port =
      Port.open({:spawn_executable, command}, [:binary, :exit_status, :use_stdio, args: args])

    Port.command(port, input <> "\n")
    collect(port, [], System.monotonic_time(:millisecond) + timeout)
  end

  defp collect(port, acc, deadline) do
    left = max(deadline - System.monotonic_time(:millisecond), 0)

    receive do
      {^port, {:data, data}} -> collect(port, [acc, data], deadline)
      {^port, {:exit_status, 0}} -> {:ok, acc |> IO.iodata_to_binary() |> String.trim_trailing()}
      {^port, {:exit_status, 3}} -> {:error, :no_enclave}
      {^port, {:exit_status, 4}} -> {:error, :refused}
      {^port, {:exit_status, 5}} -> {:error, :invalid}
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
