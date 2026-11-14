defmodule KomkiConnector.TransportTest do
  use ExUnit.Case, async: true

  alias KomkiConnector.Transport

  test "https always, http only to loopback" do
    assert Transport.secret_ok?("https://risapi3.komuna.net/web/")
    assert Transport.secret_ok?("http://127.0.0.1:4010/")
    assert Transport.secret_ok?("http://127.8.9.10:4010/")
    assert Transport.secret_ok?("http://localhost:4010/")
    assert Transport.secret_ok?("http://[::1]:4010/")

    refute Transport.secret_ok?("http://risapi3.komuna.net/web/")
    refute Transport.secret_ok?("http://10.0.0.1/")
    refute Transport.secret_ok?("https:///nohost")
    refute Transport.secret_ok?("ftp://127.0.0.1/")
    refute Transport.secret_ok?("kein url")
  end
end
