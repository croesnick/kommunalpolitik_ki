defmodule Mix.Tasks.KomkiMock.Serve do
  @shortdoc "Startet einen Mock als eigenständigen Dienst"

  @moduledoc """
  Starts one mock as a standalone OS process, so agents that drive the
  real CLIs as subprocesses can reach it. Runs until the process is
  terminated.

      mix komki_mock.serve --adapter KomkiMock.Adapters.Notes --dir <state-dir>
                           [--seed default] [--data-port 0] [--control-port 0]

  An existing `state.json` in the state directory wins over `--seed`. The
  ports land in `<state-dir>/ports.json` and on stdout.
  """

  use Mix.Task

  @switches [
    adapter: :string,
    dir: :string,
    seed: :string,
    data_port: :integer,
    control_port: :integer
  ]

  @impl true
  def run(argv) do
    Mix.Task.run("app.start")

    with {:ok, opts} <- parse(argv),
         {:ok, server} <- KomkiMock.Server.start_link(opts) do
      %{data: data, control: control} = KomkiMock.Server.ports(server)

      Mix.shell().info(
        "komki_mock: Daten auf http://127.0.0.1:#{data}/, Steuerung auf http://127.0.0.1:#{control}/ (Zustand: #{opts[:dir]})"
      )

      Process.sleep(:infinity)
    else
      {:error, message} when is_binary(message) -> Mix.raise("komki_mock: " <> message)
      {:error, reason} -> Mix.raise("komki_mock: Start fehlgeschlagen: #{inspect(reason)}")
    end
  end

  defp parse(argv) do
    case OptionParser.parse(argv, strict: @switches) do
      {opts, [], []} ->
        with {:ok, adapter} <- adapter(opts[:adapter]),
             dir when is_binary(dir) <- opts[:dir] || {:error, usage()} do
          {:ok, opts |> Keyword.put(:adapter, adapter) |> Keyword.put(:dir, Path.expand(dir))}
        end

      _ ->
        {:error, usage()}
    end
  end

  defp adapter(nil), do: {:error, usage()}

  defp adapter(name) do
    module = Module.safe_concat([name])

    if Code.ensure_loaded?(module) and function_exported?(module, :handle, 2),
      do: {:ok, module},
      else: {:error, "kein Adapter: #{name}"}
  rescue
    ArgumentError -> {:error, "kein Adapter: #{name}"}
  end

  defp usage,
    do:
      "Aufruf: mix komki_mock.serve --adapter <Modul> --dir <Verzeichnis> [--seed <name>] [--data-port <n>] [--control-port <n>]"
end
