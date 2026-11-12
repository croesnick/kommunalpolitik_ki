defmodule RatsprojekteWeb.HostPruefungTest do
  use ExUnit.Case, async: false

  import Plug.Test

  alias RatsprojekteWeb.HostPruefung

  setup do
    Application.delete_env(:ratsprojekte, :erlaubte_hosts)
    on_exit(fn -> Application.put_env(:ratsprojekte, :erlaubte_hosts, :alle) end)
  end

  test "localhost und 127.0.0.1 kommen durch" do
    for host <- ["localhost", "127.0.0.1"] do
      conn = HostPruefung.call(%{conn(:get, "/") | host: host}, [])
      refute conn.halted
    end
  end

  test "jeder andere Host (DNS-Rebinding) bekommt 421" do
    for host <- ["evil.example", "127.0.0.1.nip.io", "0.0.0.0"] do
      conn = HostPruefung.call(%{conn(:get, "/") | host: host}, [])
      assert conn.halted
      assert conn.status == 421
    end
  end
end
