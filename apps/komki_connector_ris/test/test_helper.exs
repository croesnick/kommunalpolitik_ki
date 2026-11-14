# The recording proxy, extractors, and generator are standalone
# scripts (startable outside the tests as well) and are only loaded here.
Code.require_file("../priv/gartenstadt_daten.exs", __DIR__)
Code.require_file("../priv/ris_cassettes.exs", __DIR__)
Code.require_file("../priv/ris_ngramm.exs", __DIR__)
Code.require_file("../priv/ris_recorder.exs", __DIR__)
Code.require_file("../priv/ris_gartenstadt.exs", __DIR__)
Code.require_file("../priv/ris_skeleton.exs", __DIR__)
Code.require_file("../priv/ris_struktur.exs", __DIR__)

defmodule KomkiConnectorRis.RisMock do
  @moduledoc false
  # The RIS mock on the mock runtime (apps/komki_mock), started under the
  # test supervisor with a state directory of its own. The modes of the
  # former mock_ris.exs map onto runtime scenarios and adapters.

  import ExUnit.Callbacks, only: [on_exit: 1, start_supervised!: 1]

  alias KomkiMock.Adapters.{Replay, Ris}
  alias KomkiMock.Server

  @spec start(:ok | :error500 | :slow | {:replay, Path.t()}) :: {pid(), :inet.port_number()}
  def start(mode) do
    dir = Path.join(System.tmp_dir!(), "kmris-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf(dir) end)

    {adapter, seed, scenario} = spec(mode)
    opts = [adapter: adapter, dir: dir, seed: seed]
    server = start_supervised!(Supervisor.child_spec({Server, opts}, id: make_ref()))
    if scenario, do: {:ok, _} = Server.scenario(server, scenario)

    {server, Server.ports(server).data}
  end

  defp spec(:ok), do: {Ris, "default", nil}
  defp spec(:error500), do: {Ris, "default", "error"}
  defp spec(:slow), do: {Ris, "default", "slow"}
  defp spec({:replay, dir}), do: {Replay, Path.expand(dir), nil}
end

ExUnit.start(capture_log: true)
