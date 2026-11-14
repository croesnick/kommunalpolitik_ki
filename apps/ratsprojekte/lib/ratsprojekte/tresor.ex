defmodule Ratsprojekte.Tresor do
  @moduledoc """
  `SealedEnvelope.KeyAgreement` provider over the program `komki-tresor`
  (ADR 0004: „dafür ruft der Hub `komki-tresor` als Programm auf“). The
  program holds the Secure Enclave key and performs the key agreement only
  after Touch ID or the Mac's password; plaintext never reaches it. Key
  material goes over stdin/stdout, only the prompt reason is an argument.

  This mirrors `KomkiCli.Tresor.Core` for the one program protocol, without
  depending on komki (Unix principle, AGENTS.md §2).

  Options: `:programm` (default `programm/0`), `:reason` (needed for
  `agree/3`), `:timeout`.
  """

  @behaviour SealedEnvelope.KeyAgreement

  @recipient_timeout_ms 10_000
  # agree waits for Touch ID or the password.
  @agree_timeout_ms 120_000
  @shared_secret_bytes 32

  @type error ::
          :missing_bin | :no_enclave | :refused | :invalid | :timeout | {:failed, integer()}

  @doc """
  `komki-tresor` inside the release (`make ratsprojekte` copies it to
  `bin/`), otherwise in PATH; the application env `:ratsprojekte, :tresor`
  wins. nil if it is nowhere.
  """
  @spec programm() :: String.t() | nil
  def programm do
    beside =
      System.get_env("RELEASE_ROOT") &&
        Path.join(System.get_env("RELEASE_ROOT"), "bin/komki-tresor")

    cond do
      configured = Application.get_env(:ratsprojekte, :tresor) -> configured
      beside && File.exists?(beside) -> beside
      true -> System.find_executable("komki-tresor")
    end
  end

  @doc "Error as text for people, without a value."
  @spec beschreiben(term()) :: String.t()
  def beschreiben(:missing_bin), do: "komki-tresor nicht gefunden (make ratsprojekte baut es mit)"
  def beschreiben(:no_enclave), do: "dieser Mac hat keine Secure Enclave"
  def beschreiben(:refused), do: "Freigabe per Touch ID oder Passwort verweigert oder abgebrochen"
  def beschreiben(:invalid), do: "Schlüssel ungültig oder von einem anderen Mac"
  def beschreiben(:timeout), do: "keine Freigabe innerhalb von zwei Minuten"
  def beschreiben({:failed, code}), do: "komki-tresor fehlgeschlagen (exit #{code})"
  def beschreiben(_other), do: "Schlüssel nicht lesbar"

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

  defp run(args, input, timeout, opts) do
    case Keyword.get_lazy(opts, :programm, &programm/0) do
      nil -> {:error, :missing_bin}
      command -> spawn(command, args, input, timeout)
    end
  end

  # stderr of the program stays with the caller's terminal or log (messages
  # without values); stdout carries exactly one line.
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
