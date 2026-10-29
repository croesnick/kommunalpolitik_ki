defmodule KomkiConnector.Text do
  @moduledoc """
  Die deutschen Texte der komki-Seite: einzige Quelle fuer die festen
  Fehlertexte der geschlossenen Codes (`describe/1`), die Transport-
  Details des Vermittlers und die Parameter-Fehler der Vermittler-Seite.

  Implementiert das `Sidecar.Texts`-Verhalten; der Vermittler und
  `komki_cli` geben es an `Sidecar.Client.call/6` und
  `Sidecar.Params.check/3` weiter. Diese Texte erreichen das Modell —
  aenderungen nur mit Integrator-Ruecksprache (CONTRACT.md §3).
  """

  @behaviour Sidecar.Texts

  @impl true
  def describe("bad-request"), do: "Anfrage ungültig"
  def describe("unknown-op"), do: "unbekannte Operation"
  def describe("not-found"), do: "nicht gefunden"
  def describe("upstream-error"), do: "Fehler beim angebundenen Dienst"
  def describe("upstream-timeout"), do: "angebundener Dienst antwortet nicht"
  def describe("credential-missing"), do: "Zugangsdaten fehlen"
  def describe("forbidden-path"), do: "Pfad nicht erlaubt"
  def describe("too-large"), do: "Antwort oder Anfrage zu groß"
  def describe("unauthorized"), do: "Aufruf nicht berechtigt"
  def describe(_code), do: "interner Fehler"

  @impl true
  def transport(:no_token, _reason), do: "Connector-Token fehlt"
  def transport(:request_too_large, _reason), do: "Anfrage ueberschreitet 1 MiB"
  def transport(:connect_timeout, _reason), do: "Connector antwortet nicht"

  def transport(:connect_failed, reason),
    do: "Connector nicht erreichbar: #{inspect(reason)}"

  def transport(:send_failed, reason), do: "Senden fehlgeschlagen: #{inspect(reason)}"

  def transport(:recv_timeout, _reason), do: "Connector-Antwort nach Timeout"

  def transport(:recv_failed, reason), do: "Empfangen fehlgeschlagen: #{inspect(reason)}"

  def transport(:bad_reply_frame, _reason), do: "ungueltiger Antwort-Frame"

  def transport(:reply_mismatch, _reason), do: "Antwort passt nicht zur Anfrage"

  @impl true
  def params_error(:unknown_fields, %{names: names}),
    do: "unbekannte Felder: #{Enum.join(Enum.sort(names), ", ")}"

  def params_error(:not_object, _info), do: "Parameter muessen ein Objekt sein"

  def params_error(:missing_required, %{name: name}), do: "Pflichtfeld fehlt: #{name}"

  def params_error(:invalid_utf8, %{name: name}), do: "#{name}: kein gueltiges UTF-8"

  def params_error(:too_long, %{name: name, max: max}), do: "#{name}: laenger als #{max} Zeichen"

  def params_error(:blank, %{name: name}), do: "#{name}: leer"

  def params_error(:bad_format, %{name: name}), do: "#{name}: unzulaessiges Format"

  def params_error(:out_of_range, %{name: name, min: min, max: max}),
    do: "#{name}: ausserhalb #{min}..#{max}"

  def params_error(:wrong_type, %{name: name, type: type}), do: "#{name}: erwartet #{type}"
end
