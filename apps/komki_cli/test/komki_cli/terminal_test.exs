defmodule KomkiCli.TerminalTest do
  # Ticket #132: pi-Ausgabe darf keine Steuersequenzen ans Terminal tragen.
  use ExUnit.Case, async: true

  alias KomkiCli.Terminal

  test "Klartext, Umlaute, Zeilenumbruch und Tab bleiben" do
    assert Terminal.sanitize("Bahnhofstraße\n\tTOP 3") == "Bahnhofstraße\n\tTOP 3"
  end

  test "OSC 52 (Zwischenablage) wird entfernt, mit BEL und mit ST" do
    assert Terminal.sanitize("a\e]52;c;c2VjcmV0\ab") == "ab"
    assert Terminal.sanitize("a\e]52;c;c2VjcmV0\e\\b") == "ab"
  end

  test "OSC 8 (Hyperlink) wird entfernt, der Linktext bleibt" do
    link = "\e]8;;https://evil.example/?q=geheim\e\\hier\e]8;;\e\\"
    assert Terminal.sanitize(link) == "hier"
  end

  test "CSI, Wagenruecklauf und unterminiertes OSC werden entfernt" do
    assert Terminal.sanitize("\e[31mrot\e[0m\rx") == "rotx"
    assert Terminal.sanitize("ok\e]52;c;abc") == "ok"
  end

  test "C1-Steuerzeichen und ungueltiges UTF-8 tragen keine Sequenz" do
    assert Terminal.sanitize("a\u009B31mb") == "a31mb"
    refute Terminal.sanitize(<<"a", 0x9B, "b">>) =~ <<0x9B>>
  end
end
