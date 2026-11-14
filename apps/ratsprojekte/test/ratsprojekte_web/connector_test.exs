defmodule RatsprojekteWeb.ConnectorTest do
  use ExUnit.Case, async: false

  import Ratsprojekte.Betrieb

  alias Ratsprojekte.{Ort, Sperre}

  setup do
    home = home!()
    eingerichtet!(home)
    sperre = sperre!(home, sperre_nach: 400)
    start_supervised!({RatsprojekteWeb.Connector, home: home, sperre: sperre})
    token = 16 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
    hash = :sha256 |> :crypto.hash(token) |> Base.encode16(case: :lower)
    Ort.schreiben!(Ort.token_hash(home), hash <> "\n")
    %{home: home, sperre: sperre, token: token}
  end

  test "Socket hat die Rechte 0600", %{home: home} do
    assert {:ok, %File.Stat{mode: mode}} = File.stat(Ort.connector(home))
    assert Bitwise.band(mode, 0o777) == 0o600
  end

  test "ohne, mit falschem oder ohne hinterlegten Token: 401", %{home: home, token: token} do
    assert {401, _} = post(home, nil)
    assert {401, _} = post(home, "falsch")
    File.rm!(Ort.token_hash(home))
    assert {401, _} = post(home, token)
  end

  test "gesperrt: 503 „gesperrt“, nichts gepuffert", %{home: home, token: token} do
    assert {503, body} = post(home, token)
    assert body =~ ~s("status":"gesperrt")
  end

  test "offen: nur die Connector-Route, sonst nichts", %{home: home, sperre: sperre, token: token} do
    {:ok, _} = Sperre.oeffnen(sperre)
    assert {501, _} = post(home, token)
    assert {404, _} = post(home, token, "/")
  end

  test "Connector-Aufrufe halten den Hub nicht offen", %{home: home, sperre: sperre, token: token} do
    Phoenix.PubSub.subscribe(Ratsprojekte.PubSub, Sperre.topic())
    {:ok, _} = Sperre.oeffnen(sperre)

    # 500 ms of connector calls against a lock after 400 ms.
    for _ <- 1..10 do
      post(home, token)
      Process.sleep(50)
    end

    assert_receive :gesperrt, 1_000
  end

  defp post(home, token, path \\ "/connector/fakt_vorschlagen") do
    auth = if token, do: "Authorization: Bearer #{token}\r\n", else: ""

    request =
      "POST #{path} HTTP/1.1\r\nHost: localhost\r\n#{auth}Content-Length: 2\r\nConnection: close\r\n\r\n{}"

    {:ok, sock} = :gen_tcp.connect({:local, Ort.connector(home)}, 0, [:binary, active: false])
    :ok = :gen_tcp.send(sock, request)
    response = recv(sock, "")
    [head, body] = String.split(response, "\r\n\r\n", parts: 2)
    [_, status | _] = String.split(head, " ")
    {String.to_integer(status), body}
  end

  defp recv(sock, acc) do
    case :gen_tcp.recv(sock, 0, 2_000) do
      {:ok, chunk} -> recv(sock, acc <> chunk)
      {:error, :closed} -> acc
    end
  end
end
