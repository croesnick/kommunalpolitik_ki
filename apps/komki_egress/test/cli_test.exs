defmodule KomkiEgress.CLITest do
  use ExUnit.Case, async: false

  alias KomkiEgress.CLI

  defp free_port do
    {:ok, socket} = :gen_tcp.listen(0, ip: {127, 0, 0, 1})
    {:ok, port} = :inet.port(socket)
    :gen_tcp.close(socket)
    port
  end

  test "gültige Zeile startet die Listener und nennt die Ports" do
    port = free_port()
    line = ~s({"ports": {"#{port}": {"connector": "web", "allow": ["a.de:443"]}}}\n)

    assert {:ok, [^port]} = CLI.start(line)
    assert {:ok, socket} = :gen_tcp.connect({127, 0, 0, 1}, port, [:binary, active: false])
    :gen_tcp.close(socket)
  end

  test "leeres stdin ist ein Konfigurationsfehler" do
    assert {:error, message} = CLI.start(:eof)
    assert message =~ "keine Konfiguration"
  end

  test "ungültiges JSON ist ein Konfigurationsfehler" do
    assert {:error, "Konfiguration ist kein gültiges JSON"} = CLI.start("{kaputt")
  end

  test "belegter Port ist ein Startfehler" do
    {:ok, busy} = :gen_tcp.listen(0, ip: {127, 0, 0, 1})
    {:ok, port} = :inet.port(busy)
    line = ~s({"ports": {"#{port}": {"connector": "web", "allow": ["a.de:443"]}}})

    assert {:error, message} = CLI.start(line)
    assert message =~ "Port #{port} lässt sich nicht binden"
    :gen_tcp.close(busy)
  end
end
