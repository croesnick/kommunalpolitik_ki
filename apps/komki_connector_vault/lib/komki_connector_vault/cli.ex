defmodule KomkiConnectorVault.CLI do
  @moduledoc """
  Escript-Einstieg `komki-connector-vault` (CONTRACT.md §4):

      komki-connector-vault --socket <pfad> --vault-dir <pfad>

  Liest zuerst die Credentials von stdin (eine JSON-Zeile, hier `{}`),
  bindet dann den Socket und bedient Anfragen, bis SIGTERM kommt. Log
  auf stderr, ohne Payloads. Bei Fehlern: Meldung auf stderr, Exit 1.
  """

  alias KomkiConnector.Launch
  alias Sidecar.Server

  @spec main([String.t()]) :: no_return()
  def main(argv) do
    log_to_stderr()

    with {:ok, socket, vault_dir} <- parse(argv),
         {:ok, creds} <- Server.read_credentials() do
      case Launch.run(KomkiConnectorVault, socket, vault_dir, creds) do
        {:error, reason} -> fail(to_string_reason(reason))
      end
    else
      {:error, message} -> fail(message)
    end
  end

  defp parse(argv) do
    case OptionParser.parse(argv, strict: [socket: :string, vault_dir: :string]) do
      {opts, [], []} ->
        with {:ok, socket} <- required(opts, :socket, "--socket"),
             {:ok, vault_dir} <- required(opts, :vault_dir, "--vault-dir") do
          {:ok, socket, vault_dir}
        end

      _ ->
        {:error, "Aufruf: komki-connector-vault --socket <pfad> --vault-dir <pfad>"}
    end
  end

  defp required(opts, key, flag) do
    case Keyword.fetch(opts, key) do
      {:ok, value} when value != "" -> {:ok, value}
      _ -> {:error, "#{flag} fehlt"}
    end
  end

  defp to_string_reason(reason) when is_binary(reason), do: reason
  defp to_string_reason(reason), do: inspect(reason)

  # CONTRACT.md §4: Log auf stderr (komki up leitet es in die Logdatei um).
  defp log_to_stderr do
    _ = :logger.remove_handler(:default)

    _ =
      :logger.add_handler(:default, :logger_std_h, %{
        config: %{type: :standard_error},
        # Ohne explizite Filter setzt OTP fuer die ID :default nur
        # otp/sasl-Domains durch — Elixir-Logs gingen verloren.
        filter_default: :log,
        filters: [],
        formatter: Logger.default_formatter()
      })

    :ok
  end

  @spec fail(String.t()) :: no_return()
  defp fail(message) do
    IO.puts(:stderr, "komki-connector-vault: " <> message)
    System.halt(1)
  end
end
