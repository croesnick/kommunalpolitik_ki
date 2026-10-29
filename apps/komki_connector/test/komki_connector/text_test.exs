defmodule KomkiConnector.TextTest do
  @moduledoc """
  Die deutschen Modell- und Nutzer-Texte, exakt gepinnt: das Vokabular,
  das der Vermittler in den Modellkontext laesst, lebt seit der
  Sidecar-Extraktion hier statt in `KomkiConnector.Frame.describe/1`.
  """

  use ExUnit.Case, async: true

  alias KomkiConnector.Text

  test "describe: die festen Texte der geschlossenen Codes" do
    assert Text.describe("bad-request") == "Anfrage ungültig"
    assert Text.describe("unknown-op") == "unbekannte Operation"
    assert Text.describe("not-found") == "nicht gefunden"
    assert Text.describe("upstream-error") == "Fehler beim angebundenen Dienst"
    assert Text.describe("upstream-timeout") == "angebundener Dienst antwortet nicht"
    assert Text.describe("credential-missing") == "Zugangsdaten fehlen"
    assert Text.describe("forbidden-path") == "Pfad nicht erlaubt"
    assert Text.describe("too-large") == "Antwort oder Anfrage zu groß"
    assert Text.describe("unauthorized") == "Aufruf nicht berechtigt"
    assert Text.describe("internal") == "interner Fehler"
    assert Text.describe("gibts-nicht") == "interner Fehler"
  end

  test "transport: die Details der Vermittler-Seite" do
    assert Text.transport(:no_token, nil) == "Connector-Token fehlt"
    assert Text.transport(:request_too_large, nil) == "Anfrage ueberschreitet 1 MiB"
    assert Text.transport(:connect_timeout, :timeout) == "Connector antwortet nicht"

    assert Text.transport(:connect_failed, :enoent) ==
             "Connector nicht erreichbar: :enoent"

    assert Text.transport(:send_failed, :econnaborted) ==
             "Senden fehlgeschlagen: :econnaborted"

    assert Text.transport(:recv_timeout, :timeout) == "Connector-Antwort nach Timeout"

    assert Text.transport(:recv_failed, :closed) ==
             "Empfangen fehlgeschlagen: :closed"

    assert Text.transport(:bad_reply_frame, nil) == "ungueltiger Antwort-Frame"
    assert Text.transport(:reply_mismatch, nil) == "Antwort passt nicht zur Anfrage"
  end

  test "params_error: die deutschen Parameter-Fehler" do
    assert Text.params_error(:unknown_fields, %{names: ["b", "a"]}) == "unbekannte Felder: a, b"
    assert Text.params_error(:not_object, %{}) == "Parameter muessen ein Objekt sein"
    assert Text.params_error(:missing_required, %{name: "text"}) == "Pflichtfeld fehlt: text"
    assert Text.params_error(:invalid_utf8, %{name: "text"}) == "text: kein gueltiges UTF-8"

    assert Text.params_error(:too_long, %{name: "text", max: 200}) ==
             "text: laenger als 200 Zeichen"

    assert Text.params_error(:blank, %{name: "text"}) == "text: leer"
    assert Text.params_error(:bad_format, %{name: "text"}) == "text: unzulaessiges Format"

    assert Text.params_error(:out_of_range, %{name: "limit", min: 1, max: 20}) ==
             "limit: ausserhalb 1..20"

    assert Text.params_error(:wrong_type, %{name: "limit", type: :integer}) ==
             "limit: erwartet integer"
  end
end
