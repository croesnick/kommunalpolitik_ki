defmodule KomkiCli.TresorNativeTest do
  @moduledoc """
  Komponenten-Test des echten Programms `priv/komki-tresor` (Ticket #475):
  nicht-interaktive Pfade und Argumentverarbeitung, vor allem die
  Zusammensetzung des Freigabe-Texts aus Siegel-Fingerabdruck,
  Anfrage-Kennung und als unvertraut gekennzeichnetem Aufrufertext. Der
  echte Touch-ID-Dialog braucht die Secure Enclave und einen Menschen an der
  Maschine und laeuft hier nie (docs/echte-hardware.md).

  Ohne gebautes Programm (Linux-CI ohne swiftc) ueberspringt der Test.
  """

  use ExUnit.Case, async: true

  alias KomkiCli.Tresor
  alias KomkiCli.Tresor.Core

  # Core.binary/1 fragt die Application-Env nicht: es findet das echte
  # Programm aus dem priv-Verzeichnis, nicht den Fake aus test_helper.exs.
  setup_all do
    case Core.binary(:komki_cli) do
      nil -> [skip: "komki-tresor nicht gebaut (macOS mit swiftc: mix compile)"]
      command -> %{command: command}
    end
  end

  # ref und eph aus einem echten ktv2-Siegel (Fake-Programm mit echtem ECDH):
  # dasselbe Material, aus dem das Programm den Fingerabdruck bildet.
  defp envelope! do
    assert {:ok, sealed} = Tresor.seal("kanarienwert-für-tests")
    assert "ktv2." <> rest = sealed
    assert {:ok, json} = Base.decode64(rest)
    assert {:ok, %{"key" => key, "eph" => eph}} = JSON.decode(json)
    assert {:ok, ref} = Base.decode64(key)
    assert {:ok, eph} = Base.decode64(eph)
    {ref, eph}
  end

  # Erste 8 Hexzeichen von SHA-256 ueber ref und eph (#475): der Test pinnt
  # das Format unabhaengig von der Implementierung auf beiden Seiten.
  defp fingerprint(ref, eph) do
    :sha256 |> :crypto.hash(ref <> eph) |> Base.encode16(case: :lower) |> binary_part(0, 8)
  end

  # Ein gueltiger P-256-Punkt fuer stdin; das Programm prueft die Kurve.
  defp point do
    {public, _private} = :crypto.generate_key(:ecdh, :secp256r1)
    public
  end

  # Programm ohne Terminal: stdin/stdout ueber einen Port, mit Frist, damit
  # kein Test haengen bleibt. Ein echter Dialog kann dabei nie aufgehen:
  # Der Aufruf scheitert vorher (exit 2), oder die Eingabe ist unbrauchbar
  # (exit 5), oder der Mac hat keine Secure Enclave (exit 3).
  defp run(command, args, input) do
    port =
      Port.open({:spawn_executable, command}, [:binary, :exit_status, :use_stdio, args: args])

    Port.command(port, input <> "\n")
    collect(port, "")
  end

  defp collect(port, acc) do
    receive do
      {^port, {:data, data}} -> collect(port, acc <> data)
      {^port, {:exit_status, code}} -> {acc, code}
    after
      10_000 ->
        Port.close(port)
        {"", :timeout}
    end
  end

  test "agree ohne Anfrage-Kennung ist kein gueltiger Aufruf mehr", %{command: command} do
    # Der Angriff aus dem Ticket: `echo "<ref> <eph>" | komki-tresor agree
    # --reason "..."` — diese Signatur faellt auf die Aufrufpruefung (exit 2)
    # und kann keinen Dialog mehr ausloesen.
    {out, code} =
      System.cmd(command, ["agree", "--reason", "ratsprojekte entsperren"],
        stderr_to_stdout: true
      )

    assert code == 2
    assert out =~ "Aufruf:"
  end

  test "agree mit unzulaessiger Kennung ist kein gueltiger Aufruf", %{command: command} do
    # Die Kennung ist Dialog-Text: kurz und schlicht, sonst verwischt sie
    # die Zusammensetzung (#475).
    for kennung <- ["", "mit leer;zeichen", String.duplicate("A", 40), "zeilenumbruch\nx"] do
      {_out, code} =
        System.cmd(command, ["agree", "--reason", "x", "--nonce", kennung],
          stderr_to_stdout: true
        )

      assert code == 2
    end
  end

  test "agree mit gueltigen Argumenten gibt kein Geheimnis her", %{command: command} do
    {out, code} = run(command, ["agree", "--reason", "x", "--nonce", "AB23CD45"], "kein-base64")

    # Weder Aufruffehler (2) noch Geheimnis auf stdout; je nach Mac endet der
    # Lauf an der fehlenden Enclave (3) oder am ungueltigen Schluessel (5).
    # Ein Dialog kann mit dieser Eingabe nie aufgehen.
    assert code in [3, 5]
    assert out == ""
  end

  test "prompt setzt den Freigabe-Text zusammen, unabhaengig vom Aufrufertext", %{
    command: command
  } do
    ref = <<0, 1, 2, 3>>
    eph = point()
    kennung = "AB23CD45"

    {text, 0} =
      run(
        command,
        ["prompt", "--reason", "komki startet den Connector web: Anzeige", "--nonce", kennung],
        Base.encode64(ref) <> " " <> Base.encode64(eph)
      )

    assert String.trim_trailing(text) ==
             "Siegel " <>
               fingerprint(ref, eph) <>
               ", Anfrage " <>
               kennung <>
               " - unvertrauter Aufrufertext: komki startet den Connector web: Anzeige"
  end

  test "prompt zu einem echten Siegel zeigt den Fingerabdruck, den komki vorrechnet",
       %{command: command} do
    {ref, eph} = envelope!()

    {text, 0} =
      run(
        command,
        ["prompt", "--reason", "Text des Aufrufers", "--nonce", "AB23CD45"],
        Base.encode64(ref) <> " " <> Base.encode64(eph)
      )

    assert text =~ "Siegel " <> fingerprint(ref, eph) <> ", Anfrage AB23CD45"
    assert text =~ "unvertrauter Aufrufertext: Text des Aufrufers"
  end

  test "prompt mit unbrauchbarer Eingabe: Schluessel ungueltig, kein Text", %{command: command} do
    {out, code} = run(command, ["prompt", "--reason", "x", "--nonce", "AB23CD45"], "kein-base64")

    assert code == 5
    assert out == ""
  end
end
