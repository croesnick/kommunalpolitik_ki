defmodule KomkiCli.Tresor.Core do
  @moduledoc """
  Tresor-Kern ohne komki (Ticket #224): versiegelt Geheimnisse ueber das
  Hilfsprogramm `komki-tresor` (Quelle `native/komki-tresor/main.swift`) und
  oeffnet sie nur nach Freigabe durch die Secure Enclave. Dieser Kern kennt
  weder komki noch den Schluesselbund und ist als Kern eines
  eigenstaendigen Pakets (`enclave_seal`) gedacht; die komki-spezifische
  Programmsuche (neben dem laufenden komki) lebt im Adapter `KomkiCli.Tresor`.
  Der Programmname `komki-tresor` und die Fehlertexte werden erst beim
  Herausloesen umbenannt; das Siegel-Praefix `ktv1.` bleibt (Format-Label).

  Der private Schluessel verlaesst die Enclave nie; im Siegel steht nur seine
  von der Enclave verschluesselte Form. Klartext geht nur ueber stdin hinein
  und stdout heraus, nie ueber argv, Umgebung oder Log.

  `opts[:command]` ersetzt das Programm (Tests); ohne Angabe gilt `binary/0`
  (mitgebautes Programm im priv-Verzeichnis, sonst PATH).
  """

  @prefix "ktv1."
  @program "komki-tresor"
  @seal_timeout_ms 10_000
  # Oeffnen wartet auf Touch ID oder Passwort.
  @open_timeout_ms 120_000

  @type error ::
          :missing_bin | :no_enclave | :refused | :invalid | :timeout | {:failed, integer()}

  @doc "Ist `text` ein Siegel (und kein Klartext)?"
  @spec sealed?(String.t()) :: boolean()
  def sealed?(text), do: String.starts_with?(text, @prefix)

  @doc """
  Ist das Siegel vollstaendig (Base64, JSON mit `key`, `eph`, `box`)?
  Prueft nur die Form, oeffnet nichts. Ein gekuerztes Siegel faellt durch.
  """
  @spec well_formed?(String.t()) :: boolean()
  def well_formed?(@prefix <> encoded) do
    with {:ok, json} <- Base.decode64(encoded),
         {:ok, %{"key" => k, "eph" => e, "box" => b}} <- JSON.decode(json) do
      Enum.all?([k, e, b], &(is_binary(&1) and match?({:ok, _}, Base.decode64(&1))))
    else
      _ -> false
    end
  end

  def well_formed?(_text), do: false

  @doc """
  Standard-Aufloesung ohne komki: das mitgebaute Programm im priv-Verzeichnis
  von `app` (Standard: die App, zu der dieser Kern gehoert), sonst PATH. nil,
  wenn es nirgends liegt. Die kanonische Pfadform (Seatbelt) ist
  Angelegenheit des Aufrufers.
  """
  @spec binary(atom() | nil) :: String.t() | nil
  def binary(app \\ Application.get_application(__MODULE__)) do
    cond do
      priv = priv_program(app) -> priv
      path = System.find_executable(@program) -> path
      true -> nil
    end
  end

  defp priv_program(nil), do: nil

  defp priv_program(app) do
    with dir when is_list(dir) <- :code.priv_dir(app),
         path = Path.join(dir, @program),
         true <- File.exists?(path) do
      path
    else
      _ -> nil
    end
  end

  @doc """
  Secure-Enclave-Verfuegbarkeit pruefen (`check`-Subkommando). Die Ausgabe
  (stdout und stderr) wird verworfen, nur der Exit-Code zaehlt. `command`
  muss existieren; die Suche ist Sache des Aufrufers (`binary/1`).
  """
  @spec check(String.t()) :: :ok | {:error, :no_enclave | {:failed, integer()}}
  def check(command) do
    case System.cmd(command, ["check"], stderr_to_stdout: true) do
      {_, 0} -> :ok
      {_, 3} -> {:error, :no_enclave}
      {_, code} -> {:error, {:failed, code}}
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
