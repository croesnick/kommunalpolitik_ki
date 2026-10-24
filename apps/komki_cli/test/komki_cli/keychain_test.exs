defmodule KomkiCli.KeychainTest do
  @moduledoc """
  Keychain-Fehlerfaelle mit Fake-Kommando (Ticket #146). `security` wird
  nie aufgerufen; das Fake-Skript spielt dessen Exit-Codes nach.
  """

  use ExUnit.Case, async: true

  alias KomkiCli.{Keychain, TestSupport}

  @kanarie "kanarienwert-fuer-tests"

  defp fake!(body) do
    path = Path.join(TestSupport.tmp_area!("komki-kc"), "security")
    File.write!(path, "#!/bin/sh\n" <> body <> "\n")
    File.chmod!(path, 0o755)
    path
  end

  test "Erfolg: Wert ohne abschliessendes Newline; Argumente wie security(1)" do
    cmd =
      fake!(
        ~s([ "$1 $2 $3 $4" = "find-generic-password -s brave-search-api -w" ] || exit 9\necho #{@kanarie})
      )

    assert {:ok, @kanarie} = Keychain.fetch("brave-search-api", command: cmd)
  end

  test "Exit 44 (errSecItemNotFound) ist :missing" do
    assert {:error, :missing} = Keychain.fetch("x", command: fake!("exit 44"))
  end

  test "leere Ausgabe ist :missing" do
    assert {:error, :missing} = Keychain.fetch("x", command: fake!("exit 0"))
  end

  test "anderer Exit-Code ist {:failed, code}; stderr landet nirgends" do
    cmd = fake!("echo #{@kanarie} >&2\nexit 51")
    assert {:error, {:failed, 51}} = Keychain.fetch("x", command: cmd)
  end

  test "Timeout beendet das Kommando" do
    cmd = fake!("exec sleep 30")
    started = System.monotonic_time(:millisecond)
    assert {:error, :timeout} = Keychain.fetch("x", command: cmd, timeout: 300)
    assert System.monotonic_time(:millisecond) - started < 5_000
  end

  test "present/2 fragt ohne -w (kein Wert)" do
    cmd = fake!(~s([ "$#" = 3 ] || exit 9\necho attribute))
    assert :ok = Keychain.present("x", command: cmd)
    assert {:error, :missing} = Keychain.present("x", command: fake!("exit 44"))
  end

  test "describe/2 nennt den Service, nie einen Wert" do
    for error <- [:missing, :timeout, {:failed, 3}] do
      text = Keychain.describe("brave-search-api", error)
      assert text =~ "brave-search-api"
      refute text =~ @kanarie
    end
  end

  test "Testumgebung: der Default ist das Fake aus test_helper, nie security" do
    assert Application.get_env(:komki_cli, :security) == "/usr/bin/false"
    assert {:error, {:failed, 1}} = Keychain.fetch("brave-search-api")
  end
end
