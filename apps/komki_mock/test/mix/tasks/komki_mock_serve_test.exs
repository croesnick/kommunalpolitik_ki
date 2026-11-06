defmodule Mix.Tasks.KomkiMock.ServeTest do
  @moduledoc "The mock as a standalone OS process, reached from outside this VM."

  use ExUnit.Case, async: true

  @moduletag :tmp_dir
  @moduletag timeout: 120_000

  test "serves data and control from its own process", %{tmp_dir: dir} do
    port =
      Port.open({:spawn_executable, System.find_executable("mix")}, [
        :binary,
        :exit_status,
        :stderr_to_stdout,
        args: ["komki_mock.serve", "--adapter", "KomkiMock.Adapters.Notes", "--dir", dir],
        cd: File.cwd!(),
        env: [{~c"MIX_ENV", ~c"test"}]
      ])

    {:os_pid, os_pid} = Port.info(port, :os_pid)
    on_exit(fn -> System.cmd("kill", ["-TERM", to_string(os_pid)]) end)

    assert_receive {^port, {:data, line}}, 60_000
    assert line =~ "komki_mock: Daten auf http://127.0.0.1:"

    %{"data" => data, "control" => control} =
      dir |> Path.join("ports.json") |> File.read!() |> JSON.decode!()

    assert {:ok, {{_, 200, _}, _, body}} = get(data, "/notes")
    assert [%{"text" => "Erste Notiz"}, _] = body |> IO.iodata_to_binary() |> JSON.decode!()
    assert {:ok, {{_, 200, _}, _, _}} = get(control, "/state")
  end

  test "rejects a call without adapter", %{tmp_dir: dir} do
    {out, status} =
      System.cmd("mix", ["komki_mock.serve", "--dir", dir],
        env: [{"MIX_ENV", "test"}],
        stderr_to_stdout: true
      )

    assert status != 0
    assert out =~ "Aufruf: mix komki_mock.serve"
  end

  defp get(port, path),
    do:
      :httpc.request(
        :get,
        {~c"http://127.0.0.1:#{port}#{path}", [{~c"connection", ~c"close"}]},
        [],
        []
      )
end
