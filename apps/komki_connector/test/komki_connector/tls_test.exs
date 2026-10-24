defmodule KomkiConnector.TLSTest do
  use ExUnit.Case, async: true

  alias KomkiConnector.TLS

  test "System-Buendel liefert DER-Zertifikate" do
    if File.exists?(TLS.bundle_path()) do
      certs = TLS.cacerts()
      assert length(certs) > 10
      assert Enum.all?(certs, &is_binary/1)
    end
  end

  test "leeres Buendel scheitert ohne Rueckfall" do
    path = Path.join(System.tmp_dir!(), "kc-empty-#{System.unique_integer([:positive])}.pem")
    File.write!(path, "kein pem\n")
    on_exit(fn -> File.rm(path) end)
    assert_raise RuntimeError, ~r/keine CA-Zertifikate/, fn -> TLS.load!(path) end
  end
end
