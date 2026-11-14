defmodule KomkiCli.Tresor.Core do
  @moduledoc """
  Tresor core without komki: seals secrets with `SealedEnvelope` (format
  `ktv2`, the only schema instance of the format) and opens them only after
  the Secure Enclave released the key agreement.

  This module is the `SealedEnvelope.KeyAgreement` provider for the helper
  program `komki-tresor` (source `native/komki-tresor/main.swift`). The
  program does hardware only: it creates the enclave key, hands out its
  public key and returns the ECDH shared secret after Touch ID or the Mac's
  password. Plaintext stays in this process. Key material goes over
  stdin/stdout, never over argv, environment or log; only the prompt reason
  is an argument. komki-specific program discovery lives in the adapter
  `KomkiCli.Tresor`.

  Seals in the old format `ktv1` are recognised and refused (`:outdated`).
  There is no fallback: the program that could open them is gone, and the way
  forward is entering the value again with `komki secret set`.

  Options: `:command` replaces the program (default `binary/0`), `:timeout`
  bounds its runtime, `:provider` replaces the key agreement altogether
  (`{module, opts}`, tests).
  """

  @behaviour SealedEnvelope.KeyAgreement

  @outdated_prefix "ktv1."
  @program "komki-tresor"
  @recipient_timeout_ms 10_000
  # The key agreement waits for Touch ID or the password.
  @agree_timeout_ms 120_000
  @shared_secret_bytes 32

  @type error ::
          :missing_bin
          | :no_enclave
          | :refused
          | :invalid
          | :outdated
          | :timeout
          | {:failed, integer()}

  @doc "Does `text` claim to be a seal in the current format (and is it not plaintext)?"
  @spec sealed?(String.t()) :: boolean()
  def sealed?(text), do: SealedEnvelope.envelope?(text)

  @doc "Is `text` a seal in the old format `ktv1`, which komki no longer opens?"
  @spec outdated?(String.t()) :: boolean()
  def outdated?(text), do: String.starts_with?(text, @outdated_prefix)

  @doc "Is the seal complete? Checks the structure only, opens nothing."
  @spec well_formed?(String.t()) :: boolean()
  def well_formed?(text), do: SealedEnvelope.well_formed?(text)

  @doc """
  Default lookup without komki: the program built into the priv directory of
  `app` (default: the app this core belongs to), otherwise PATH. nil if it is
  nowhere. The canonical path form (Seatbelt) is the caller's business.
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
  Check Secure Enclave availability (`check` subcommand). Output (stdout and
  stderr) is discarded, only the exit code counts. `command` must exist;
  finding it is the caller's business (`binary/1`).
  """
  @spec check(String.t()) :: :ok | {:error, :no_enclave | {:failed, integer()}}
  def check(command) do
    case System.cmd(command, ["check"], stderr_to_stdout: true) do
      {_, 0} -> :ok
      {_, 3} -> {:error, :no_enclave}
      {_, code} -> {:error, {:failed, code}}
    end
  end

  @doc "Seal plaintext. No prompt: sealing only needs the public key."
  @spec seal(String.t(), keyword()) :: {:ok, String.t()} | {:error, error()}
  def seal(value, opts \\ []) when is_binary(value) do
    with :ok <- one_line(value) do
      value |> SealedEnvelope.seal(provider(opts)) |> result()
    end
  end

  defp one_line(value) do
    if value == "" or String.contains?(value, ["\n", "\r"]), do: {:error, :invalid}, else: :ok
  end

  @doc "Open a seal; macOS asks for Touch ID or the password, showing `reason`."
  @spec open(String.t(), String.t(), keyword()) :: {:ok, String.t()} | {:error, error()}
  def open(sealed, reason, opts \\ []) when is_binary(sealed) and is_binary(reason) do
    if outdated?(sealed) do
      {:error, :outdated}
    else
      sealed |> SealedEnvelope.open(provider(Keyword.put(opts, :reason, reason))) |> result()
    end
  end

  @doc "Error as text, without a value."
  @spec describe(error()) :: String.t()
  def describe(:missing_bin), do: "komki-tresor nicht gefunden (Installation prüfen)"
  def describe(:no_enclave), do: "dieser Mac hat keine Secure Enclave"
  def describe(:refused), do: "Freigabe per Touch ID oder Passwort verweigert oder abgebrochen"
  def describe(:invalid), do: "Siegel ungültig oder von einem anderen Mac"
  def describe(:outdated), do: "Siegel im alten Format ktv1; Wert neu eingeben"
  def describe(:timeout), do: "keine Freigabe innerhalb von zwei Minuten"

  def describe({:failed, code}),
    do: "komki-tresor fehlgeschlagen (exit " <> to_string(code) <> ")"

  @impl SealedEnvelope.KeyAgreement
  def recipient(opts) do
    with {:ok, out} <-
           run(["recipient"], nil, Keyword.get(opts, :timeout, @recipient_timeout_ms), opts),
         [ref, public] <- String.split(out, " "),
         {:ok, ref} <- Base.decode64(ref),
         {:ok, public} <- Base.decode64(public) do
      {:ok, ref, public}
    else
      {:error, _} = error -> error
      _ -> {:error, :invalid}
    end
  end

  @impl SealedEnvelope.KeyAgreement
  def agree(key_ref, peer_public, opts) do
    args = ["agree", "--reason", Keyword.fetch!(opts, :reason)]
    input = Base.encode64(key_ref) <> " " <> Base.encode64(peer_public)

    with {:ok, out} <- run(args, input, Keyword.get(opts, :timeout, @agree_timeout_ms), opts) do
      case Base.decode64(out) do
        {:ok, <<_::binary-size(@shared_secret_bytes)>> = shared} -> {:ok, shared}
        _ -> {:error, :invalid}
      end
    end
  end

  defp provider(opts), do: Keyword.get(opts, :provider, {__MODULE__, opts})

  # Format errors and failed authentication mean the same to the caller, and
  # an unknown provider reason (a test double's file error) carries no meaning
  # here either.
  defp result({:ok, _} = ok), do: ok
  defp result({:error, {:key_agreement, reason}}), do: {:error, agreement_error(reason)}
  defp result({:error, _format}), do: {:error, :invalid}

  defp agreement_error(reason)
       when reason in [:missing_bin, :no_enclave, :refused, :invalid, :timeout],
       do: reason

  defp agreement_error({:failed, _code} = reason), do: reason
  defp agreement_error(_reason), do: :invalid

  defp run(args, input, timeout, opts) do
    case Keyword.get_lazy(opts, :command, &binary/0) do
      nil -> {:error, :missing_bin}
      command -> spawn(command, args, input, timeout)
    end
  end

  # The program's stderr stays in the terminal (messages without values);
  # stdout carries exactly one line.
  defp spawn(command, args, input, timeout) do
    port =
      Port.open({:spawn_executable, command}, [:binary, :exit_status, :use_stdio, args: args])

    if input, do: Port.command(port, input <> "\n")
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
