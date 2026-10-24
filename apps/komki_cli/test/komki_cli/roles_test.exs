defmodule KomkiCli.RolesTest do
  @moduledoc "Multicall-Weiche (Ticket #179)."

  use ExUnit.Case, async: true

  alias KomkiCli.{Config, Roles}

  test "die Rollen heissen wie die frueheren Programme (Marker fuer die ps-Pruefung)" do
    assert Roles.names() == [
             "komki-connector-ris",
             "komki-connector-vault",
             "komki-connector-web",
             "komki-egress",
             "komki-mediator"
           ]

    for manifest <- KomkiConnector.Manifest.all(), do: assert(manifest.binary in Roles.names())
  end

  test "dispatch/1 erkennt Rollen und laesst komki-Befehle durch" do
    assert {KomkiMediator.CLI, ["--base", "/x"]} =
             Roles.dispatch(["komki-mediator", "--base", "/x"])

    assert {KomkiConnectorVault.CLI, []} = Roles.dispatch(["komki-connector-vault"])
    assert Roles.dispatch(["setup", "--demo"]) == nil
    assert Roles.dispatch([]) == nil
  end

  test "prefix/3 setzt den Rollennamen nur vor das Multicall-Programm" do
    cfg = %{
      Config.defaults("/tmp/komki-roles", komki_bin: "/opt/komki")
      | komki_bin: "/opt/komki"
    }

    assert Roles.prefix(cfg, "/opt/komki", "komki-egress") == ["komki-egress"]
    assert Roles.prefix(cfg, "/alt/komki-egress", "komki-egress") == []
    assert Roles.prefix(%{cfg | komki_bin: nil}, "/opt/komki", "komki-egress") == []
  end

  test "unter mix ist komki nicht das laufende Programm" do
    assert Config.self_komki() == nil
  end
end
