defmodule WegwerfHub.HTTPTest do
  # #491 (F22 aus dem Security-Audit #467): Der Schreibweg des Connectors
  # über den Unix-Socket. Ein Rumpf über der 64-KiB-Grenze bekommt eine
  # bestimmte 400-Antwort mit Zeile im Anfrage-Log, kein WithClauseError.
  # Wie im Betrieb: Bandit auf <home>/hub.sock, Token nur als Hash, roher
  # HTTP-Client mit Connection: close.
  use ExUnit.Case, async: true

  alias KomkiPolicy.JSON
  alias WegwerfHub.Store

  @moduletag :capture_log

  # Grenze wie WegwerfHub.HTTP (@max_body): darüber bestimmte 400-Antwort,
  # darunter normaler Geschäftsgang.
  @grenze 65_536
  @route "/connector/fakt_vorschlagen"

  setup do
    # Kurz und zufällig statt ExUnit-tmp_dir: Unix-Socket-Pfade sind auf
    # 104 Bytes begrenzt (wie Ratsprojekte.Betrieb.home!/1, #452).
    suffix = Base.hex_encode32(:crypto.strong_rand_bytes(10), case: :lower, padding: false)
    home = Path.join(System.tmp_dir!(), "wegwerf-hub-" <> suffix)
    File.mkdir!(home)
    on_exit(fn -> File.rm_rf!(home) end)

    token = 16 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
    hash = :sha256 |> :crypto.hash(token) |> Base.encode16(case: :lower)
    File.write!(Path.join(home, "token-hash"), hash <> "\n")

    socket = Path.join(home, "hub.sock")

    start_supervised!(
      {Bandit, plug: {WegwerfHub.HTTP, dir: home}, scheme: :http, ip: {:local, socket}, port: 0}
    )

    %{home: home, socket: socket, token: token}
  end

  # Angriffsweg aus dem Audit: 65 537 Bytes, ein Byte über der Grenze.
  test "Rumpf über der Grenze: 400 und Zeile im Anfrage-Log", %{
    home: home,
    socket: socket,
    token: token
  } do
    assert {400, "ungültige Anfrage: Rumpf über 64 KiB"} ==
             anfrage(socket, token, vorschlag_rumpf(@grenze + 1))

    assert Store.anfragen(home) == 1
    assert File.read!(Path.join(home, "anfragen.log")) =~ " POST #{@route} 400"
  end

  test "Rumpf von genau der Grenze: 201, Vorschlag im Bestand", %{
    home: home,
    socket: socket,
    token: token
  } do
    assert {201, "{\"status\":\"vorgeschlagen\"}"} ==
             anfrage(socket, token, vorschlag_rumpf(@grenze))

    assert Store.anfragen(home) == 1
    assert [%{"titel" => titel}] = Store.vorschlaege(home)
    assert String.starts_with?(titel, "Radweg")
  end

  test "gültiger Vorschlag: 201, Vorschlag im Bestand", %{
    home: home,
    socket: socket,
    token: token
  } do
    assert {201, "{\"status\":\"vorgeschlagen\"}"} ==
             anfrage(socket, token, JSON.canonical(vorschlag("Radweg an der Bahnhofstraße")))

    assert Store.anfragen(home) == 1
    assert [%{"titel" => "Radweg an der Bahnhofstraße"}] = Store.vorschlaege(home)
  end

  test "Rumpf ohne JSON: 400 und Zeile im Anfrage-Log", %{
    home: home,
    socket: socket,
    token: token
  } do
    assert {400, "ungültige Anfrage: ungültiges JSON"} == anfrage(socket, token, "kein json")

    assert Store.anfragen(home) == 1
  end

  # -------------------------------------------------------------------------
  # Werkzeuge
  # -------------------------------------------------------------------------

  # Kanonischer Vorschlags-Rumpf, auf genau `size` Bytes gebracht (der
  # Titel trägt das Füllmaterial) — so testet die Grenze allein die Größe,
  # nicht zufällig die JSON-Form.
  defp vorschlag_rumpf(size) do
    titel = "Radweg an der Bahnhofstraße"
    fehlt = size - byte_size(JSON.canonical(vorschlag(titel)))
    assert fehlt >= 0
    JSON.canonical(vorschlag(titel <> String.duplicate("x", fehlt)))
  end

  defp vorschlag(titel) do
    %{
      "titel" => titel,
      "projekt_hinweis" => "radweg-bahnhofstrasse",
      "labels" => ["web-oeffentlich@1"],
      "teile" => [
        %{
          "aussage" => "Der Gehweg an der Bahnhofstraße wird zum Radweg.",
          "quelle" => "antwort-1",
          "fundstelle" => nil
        }
      ]
    }
  end

  defp anfrage(socket, token, rumpf) do
    anfrage =
      "POST #{@route} HTTP/1.1\r\nHost: wegwerf\r\nAuthorization: Bearer #{token}\r\n" <>
        "Content-Length: #{byte_size(rumpf)}\r\nConnection: close\r\n\r\n" <> rumpf

    {:ok, sock} = :gen_tcp.connect({:local, socket}, 0, [:binary, active: false])
    :ok = :gen_tcp.send(sock, anfrage)
    antwort = empfangen(sock, "")
    :ok = :gen_tcp.close(sock)

    [kopf, antwort_rumpf] = String.split(antwort, "\r\n\r\n", parts: 2)
    [_, status | _] = String.split(kopf, " ")
    {String.to_integer(status), antwort_rumpf}
  end

  defp empfangen(sock, acc) do
    case :gen_tcp.recv(sock, 0, 2_000) do
      {:ok, chunk} -> empfangen(sock, acc <> chunk)
      {:error, :closed} -> acc
    end
  end
end
