defmodule KomkiCli.ApplicationTest do
  use ExUnit.Case, async: true

  alias KomkiCli.Application

  # Mix-Kontext (Test-VM): start/2 darf die VM nicht anhalten — No-Op-Supervisor
  # statt CLI-Dispatch. Der Release-Zweig (Mix nicht geladen) kann nicht
  # unit-getestet werden; er ist E2E vom Burrito-Pilot abgedeckt.
  test "start/2 im Mix-Kontext: No-Op-Supervisor, VM bleibt oben" do
    assert {:ok, pid} = Application.start(:normal, [])
    assert is_pid(pid)
    assert Process.alive?(pid)
  end
end
