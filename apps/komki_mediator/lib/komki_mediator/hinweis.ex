defmodule KomkiMediator.Hinweis do
  @moduledoc """
  Modellgerichtete Saetze fuer Antworten ohne Ergebnis (Ticket #166).

  Ein `deny` oder `indeterminate` ist fuer das Modell ein Endpunkt: Die
  Sperre haengt am Arbeitsraum und an seinen Bindungen, nicht an der
  Formulierung. Ohne diesen Satz suchte das Modell im Labbook S-10c zehn
  Minuten lang ueber andere Tools weiter, und nach einem abgelehnten GO
  loeste jede umformulierte Anfrage ein weiteres GO-Fenster aus (Demo
  #101). Der Satz steht im Feld `hinweis` jeder solchen Antwort; den Weg
  nach vorn beschreibt weiterhin der Remedy-Katalog der Engine.

  Diese Texte erreichen das Modell. Sie sind fest und enthalten keine
  Daten aus dem Aufruf.
  """

  @doc "Hinweis zu einer Antwort ohne Ergebnis: `:deny`, `:go_refused` oder `:go_timeout`."
  @spec text(:deny | :go_refused | :go_timeout) :: String.t()
  def text(:deny) do
    "Gesperrt: Dieser Aufruf ist in diesem Arbeitsraum nicht zulässig. " <>
      "Ein anderes Werkzeug oder eine umformulierte Anfrage führt nicht zum Ziel, " <>
      "denn die Sperre hängt am Arbeitsraum, nicht an der Formulierung. " <>
      "Versuche es nicht erneut. Sag der nutzenden Person, was gesperrt ist, " <>
      "und nenne die Schritte aus remedies."
  end

  def text(:go_refused) do
    "Die nutzende Person hat diesen Aufruf abgelehnt. " <>
      "Frag nicht erneut, auch nicht mit anderen Worten oder über ein anderes Werkzeug. " <>
      "Arbeite ohne dieses Ergebnis weiter oder beende deine Antwort."
  end

  def text(:go_timeout) do
    "Für diesen Aufruf kam keine Freigabe. Frag nicht erneut. " <>
      "Sag der nutzenden Person, dass der Aufruf ihre Freigabe braucht, " <>
      "und arbeite ohne dieses Ergebnis weiter."
  end
end
