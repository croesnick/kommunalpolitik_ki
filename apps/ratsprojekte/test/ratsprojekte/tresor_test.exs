defmodule Ratsprojekte.TresorTest do
  @moduledoc """
  Der Hub als Aufrufer des Programm-Protokolls (#475): `agree/3` uebergibt
  je Freigabe eine frische Anfrage-Kennung und schreibt Fingerabdruck und
  Kennung ins Terminal, damit die Person beide im Touch-ID-Dialog abgleichen
  kann. Das echte Programm spielt ein Aufzeichnungs-Skript nach — die
  Secure Enclave laeuft hier nie.
  """

  use ExUnit.Case, async: true

  import ExUnit.CaptureIO, only: [with_io: 1]

  # Aufzeichnendes Programm: argv und stdin mitschreiben, ein gueltiges
  # 32-Byte-Geheimnis (Base64) ausgeben.
  defp programm!(dir) do
    path = Path.join(dir, "komki-tresor")

    File.write!(path, """
    #!/bin/sh
    echo "$@" >> #{dir}/argv
    read -r line
    echo "$line" >> #{dir}/stdin
    printf '%s\\n' '#{Base.encode64(<<0::size(256)>>)}'
    """)

    File.chmod!(path, 0o755)
    path
  end

  # Erste 8 Hexzeichen von SHA-256 ueber ref und eph (#475): der Test pinnt
  # das Format unabhaengig von der Implementierung.
  defp fingerabdruck(ref, eph),
    do: :sha256 |> :crypto.hash(ref <> eph) |> Base.encode16(case: :lower) |> binary_part(0, 8)

  test "agree uebergibt eine frische Anfrage-Kennung und zeigt sie im Terminal" do
    dir =
      Path.join(System.tmp_dir!(), "ratsprojekte-tresor-#{System.unique_integer([:positive])}")

    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)

    kennungen =
      for _ <- 1..2 do
        {result, abgleich} =
          with_io(fn ->
            Ratsprojekte.Tresor.agree(<<1>>, <<2>>,
              reason: "Test",
              programm: programm!(dir),
              timeout: 5000
            )
          end)

        assert {:ok, <<0::size(256)>>} = result

        # Die Kennung aus der Terminalzeile muss auch im Aufruf stehen: nur
        # dann zeigt der Dialog zu ihr passende Werte.
        [kennung] = Regex.run(~r/Anfrage ([A-Z2-7]{8}) \(/, abgleich, capture: :all_but_first)

        letzter_aufruf =
          dir
          |> Path.join("argv")
          |> File.read!()
          |> String.split("\n", trim: true)
          |> List.last()

        assert letzter_aufruf == "agree --reason Test --nonce " <> kennung

        assert abgleich ==
                 "Freigabe erbeten: Siegel " <>
                   fingerabdruck(<<1>>, <<2>>) <>
                   ", Anfrage " <>
                   kennung <>
                   " (im Touch-ID-Dialog abgleichen)\n"

        kennung
      end

    assert [erste, zweite] = kennungen
    assert erste != zweite
  end
end
