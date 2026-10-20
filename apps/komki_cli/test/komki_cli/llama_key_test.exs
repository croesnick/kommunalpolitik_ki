defmodule KomkiCli.LlamaKeyTest do
  # Ticket #136: llama-API-Key gegen Cross-Origin-Zugriff aus dem Browser.
  use ExUnit.Case, async: true

  alias KomkiCli.{Llama, Steps, TestSupport}

  setup do
    {:ok, cfg: TestSupport.fixture_cfg(TestSupport.tmp_area!("komki-llama-key"))}
  end

  test "write_key! schreibt 0600 und jeder Start bekommt einen neuen Schluessel", %{cfg: cfg} do
    k1 = Llama.write_key!(cfg)
    %File.Stat{mode: mode} = File.stat!(Llama.key_path(cfg))
    assert Bitwise.band(mode, 0o777) == 0o600
    assert {:ok, ^k1} = Llama.read_key(cfg)
    assert byte_size(k1) >= 43

    k2 = Llama.write_key!(cfg)
    refute k1 == k2
  end

  test "read_key ohne Datei ist :none", %{cfg: cfg} do
    assert Llama.read_key(cfg) == :none
  end

  test "models.json traegt den Schluessel, ohne Schluessel einen Platzhalter", %{cfg: cfg} do
    path = Path.join([cfg.pi_home, ".pi", "agent", "models.json"])

    Steps.write_models(cfg)
    assert models_key(path) == "kein-llama-key"

    key = Llama.write_key!(cfg)
    Steps.write_models(cfg)
    assert models_key(path) == key
  end

  describe "auth_required/1 gegen einen Fake-Server" do
    test "401 heisst Schluessel verlangt, 200 heisst offen" do
      assert {:ok, true} = Llama.auth_required(fake_server("401 Unauthorized"))
      assert {:ok, false} = Llama.auth_required(fake_server("200 OK"))
    end
  end

  defp models_key(path) do
    {:ok, json} = path |> File.read!() |> JSON.decode()
    json["providers"]["pi-local"]["apiKey"]
  end

  # Antwortet genau einmal mit der Statuszeile und schliesst.
  defp fake_server(status) do
    {:ok, listen} = :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}])
    {:ok, port} = :inet.port(listen)

    spawn_link(fn ->
      {:ok, sock} = :gen_tcp.accept(listen)
      {:ok, _req} = :gen_tcp.recv(sock, 0)
      :gen_tcp.send(sock, "HTTP/1.1 " <> status <> "\r\nContent-Length: 0\r\n\r\n")
      :gen_tcp.close(sock)
    end)

    port
  end
end
