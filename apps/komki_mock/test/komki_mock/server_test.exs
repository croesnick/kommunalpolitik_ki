defmodule KomkiMock.ServerTest do
  @moduledoc "The runtime against the notes adapter, over real loopback HTTP."

  use ExUnit.Case, async: true

  alias KomkiMock.Adapters.Notes
  alias KomkiMock.Server

  @moduletag :tmp_dir

  setup %{tmp_dir: dir} do
    {:ok, server} = Server.start_link(adapter: Notes, dir: dir)
    %{server: server, ports: Server.ports(server)}
  end

  describe "state" do
    test "a change survives a restart", %{server: server, ports: ports, tmp_dir: dir} do
      assert {201, _} = post(ports.data, "/notes", %{"text" => "Dritte"})
      assert {200, _} = post(ports.control, "/scenario", %{"name" => "slow", "delay_ms" => 50})
      :ok = Server.stop(server)

      {:ok, server} = Server.start_link(adapter: Notes, dir: dir, seed: "empty")
      ports = Server.ports(server)

      assert {200, notes} = get(ports.data, "/notes")
      assert Enum.map(notes, & &1["text"]) == ["Erste Notiz", "Zweite Notiz", "Dritte"]
      assert %{"scenario" => "slow", "delay_ms" => 50, "seed" => "default"} = Server.state(server)
    end

    test "reset restores the seed byte for byte", %{ports: ports, tmp_dir: dir} do
      seeded = File.read!(Path.join(dir, "state.json"))

      post(ports.data, "/notes", %{"text" => "weg damit"})
      post(ports.control, "/scenario", %{"name" => "error"})
      refute File.read!(Path.join(dir, "state.json")) == seeded

      assert {200, %{"scenario" => "ok"}} = post(ports.control, "/reset", %{})
      assert File.read!(Path.join(dir, "state.json")) == seeded
      assert {200, [_, _]} = get(ports.data, "/notes")
    end

    test "seed switches data and clears the log", %{ports: ports} do
      get(ports.data, "/notes")

      assert {200, %{"seed" => "empty"}} = post(ports.control, "/seed", %{"name" => "empty"})
      assert {200, []} = get(ports.data, "/notes")
      assert {200, [%{"path" => "/notes"}]} = get(ports.control, "/log")
      assert {404, _} = post(ports.control, "/seed", %{"name" => "nope"})
    end

    test "parallel requests stay consistent", %{ports: ports, tmp_dir: dir} do
      1..40
      |> Task.async_stream(&post(ports.data, "/notes", %{"text" => "n#{&1}"}),
        max_concurrency: 40
      )
      |> Enum.each(fn {:ok, {201, _}} -> :ok end)

      {200, notes} = get(ports.data, "/notes")
      ids = Enum.map(notes, & &1["id"])

      assert length(ids) == 42
      assert Enum.sort(ids) == Enum.to_list(1..42)

      on_disk = dir |> Path.join("state.json") |> File.read!() |> JSON.decode!()
      assert on_disk["data"]["notes"] == notes
    end

    test "an unknown initial seed refuses to start", %{tmp_dir: dir} do
      Process.flag(:trap_exit, true)

      assert {:error, {:unknown_seed, "nope"}} =
               Server.start_link(adapter: Notes, dir: Path.join(dir, "other"), seed: "nope")
    end
  end

  describe "scenarios" do
    test "error answers 500 and changes nothing", %{ports: ports} do
      post(ports.control, "/scenario", %{"name" => "error"})

      assert {500, %{"error" => "scenario error"}} = post(ports.data, "/notes", %{"text" => "x"})

      post(ports.control, "/scenario", %{"name" => "ok"})
      assert {200, [_, _]} = get(ports.data, "/notes")
    end

    test "slow waits delay_ms", %{ports: ports} do
      post(ports.control, "/scenario", %{"name" => "slow", "delay_ms" => 300})

      {micros, {200, _}} = :timer.tc(fn -> get(ports.data, "/notes") end)
      assert micros >= 300_000
    end

    test "refused closes the data port; ok reopens it on the same port", %{ports: ports} do
      assert {200, %{"scenario" => "refused"}} =
               post(ports.control, "/scenario", %{"name" => "refused"})

      assert {:error, {:failed_connect, _}} = request(:get, ports.data, "/notes")
      assert {200, _} = get(ports.control, "/state")

      post(ports.control, "/scenario", %{"name" => "ok"})
      assert {200, [_, _]} = get(ports.data, "/notes")
    end

    test "refused survives a restart", %{server: server, ports: ports, tmp_dir: dir} do
      post(ports.control, "/scenario", %{"name" => "refused"})
      :ok = Server.stop(server)

      {:ok, server} = Server.start_link(adapter: Notes, dir: dir)
      ports = Server.ports(server)

      assert {:error, {:failed_connect, _}} = request(:get, ports.data, "/notes")
    end

    test "unknown scenarios and bad delays are rejected", %{ports: ports} do
      assert {400, _} = post(ports.control, "/scenario", %{"name" => "flaky"})
      assert {400, _} = post(ports.control, "/scenario", %{"name" => "slow", "delay_ms" => -1})
      assert {200, %{"scenario" => "ok"}} = get(ports.control, "/state")
    end
  end

  describe "request log" do
    test "records method, path, query, status and scenario", %{ports: ports, tmp_dir: dir} do
      get(ports.data, "/notes?from=2026-01-01")
      get(ports.data, "/notes/99")
      post(ports.control, "/scenario", %{"name" => "error"})
      post(ports.data, "/notes", %{"text" => "x"})

      assert {200, log} = get(ports.control, "/log")

      assert [
               %{
                 "method" => "GET",
                 "path" => "/notes",
                 "query" => "from=2026-01-01",
                 "status" => 200
               },
               %{"path" => "/notes/99", "status" => 404, "scenario" => "ok"},
               %{"method" => "POST", "status" => 500, "scenario" => "error"}
             ] = log

      assert File.exists?(Path.join(dir, "requests.jsonl"))
    end
  end

  test "ports.json names both ports", %{ports: ports, tmp_dir: dir} do
    assert dir |> Path.join("ports.json") |> File.read!() |> JSON.decode!() ==
             %{"data" => ports.data, "control" => ports.control}
  end

  defp get(port, path), do: decode(request(:get, port, path))
  defp post(port, path, body), do: decode(request(:post, port, path, JSON.encode!(body)))

  defp request(:get, port, path),
    do: :httpc.request(:get, {url(port, path), [{~c"connection", ~c"close"}]}, [], [])

  defp request(:post, port, path, body) do
    :httpc.request(
      :post,
      {url(port, path), [{~c"connection", ~c"close"}], ~c"application/json", body},
      [],
      []
    )
  end

  defp url(port, path), do: ~c"http://127.0.0.1:#{port}#{path}"

  defp decode({:ok, {{_, status, _}, _headers, body}}),
    do: {status, JSON.decode!(IO.iodata_to_binary(body))}
end
