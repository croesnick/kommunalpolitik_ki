defmodule KomkiCli.BurritoLaunchTest do
  @moduledoc """
  Rollenstart unter der Burrito-Einzeldatei (Ticket #181): Startzeile und
  Profilschicht. Im Escript-Betrieb bleiben beide unveraendert.
  """

  use ExUnit.Case, async: true

  alias KomkiCli.{Config, EscriptProfile, Proc}

  @root "/Users/x/Library/Application Support/.burrito/komki_erts-17.1.1_0.1.0"

  defp burrito_cfg do
    %{
      Config.defaults("/tmp/komki-burrito", komki_bin: "/opt/komki-bin")
      | launcher: "burrito",
        runtime_root: @root,
        escript_bin: nil
    }
  end

  test "Startzeile: Binary direkt, KOMKI_INSTALL_DIR zeigt zwei Ebenen ueber die Laufzeit" do
    cmd =
      Proc.role_cmd(burrito_cfg(), "/p/egress.sb", "/opt/komki-bin", ["komki-egress"], "/home")

    assert Enum.take(cmd, 6) == [
             "/usr/bin/env",
             "-i",
             "HOME=/home",
             "PATH=/usr/bin:/bin",
             "LANG=C",
             "KOMKI_INSTALL_DIR=/Users/x/Library/Application Support"
           ]

    assert Enum.take(cmd, -2) == ["/opt/komki-bin", "komki-egress"]
    refute Enum.any?(cmd, &String.ends_with?(&1, "/escript"))
  end

  test "Escript-Betrieb: Startzeile wie bisher (escript <datei> <args>), ohne KOMKI_INSTALL_DIR" do
    cfg = %{burrito_cfg() | launcher: "escript", escript_bin: "/erl/bin/escript"}
    cmd = Proc.role_cmd(cfg, "/p/egress.sb", "/opt/komki-bin", ["komki-egress"], "/home")

    assert Enum.take(cmd, -3) == ["/erl/bin/escript", "/opt/komki-bin", "komki-egress"]
    refute Enum.any?(cmd, &String.starts_with?(&1, "KOMKI_INSTALL_DIR="))
  end

  test "Profilschicht: Binary ausfuehren, Laufzeit-Verzeichnis anlegen, .burrito lesen, COOKIE schreiben" do
    rules = EscriptProfile.runtime_for(burrito_cfg(), "/opt/komki-bin")

    assert ~s{(allow process-exec (literal "/opt/komki-bin"))} in rules
    assert ~s{(allow file-write-create (literal "#{@root}"))} in rules
    assert ~s{(allow file-read* (literal "#{Path.dirname(@root)}"))} in rules
    assert ~s{(allow file-write-data (literal "#{@root}/releases/COOKIE"))} in rules
    assert ~s{(allow file-read* (subpath "#{@root}"))} in rules
    # kein Loeschen und kein Schreiben im Laufzeit-Baum
    refute Enum.any?(rules, &(&1 =~ "file-write* (subpath"))
  end

  test "Escript-Betrieb: runtime_for/2 ist exakt runtime/2 (Profiltext bestehender Instanzen bleibt)" do
    cfg = %{burrito_cfg() | launcher: "escript", escript_bin: "/erl/bin/escript"}

    assert EscriptProfile.runtime_for(cfg, "/opt/komki-bin") ==
             EscriptProfile.runtime("/erl", "/opt/komki-bin")
  end
end
