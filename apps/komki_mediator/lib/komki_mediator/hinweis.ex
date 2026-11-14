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

  alias KomkiMediator.Go

  @doc """
  Is an engine denial of `rule` with its `remedies` a "nothing
  transmitted" case? True only for a store whose target lies outside the
  recipient circle while the catalog offers no GO (ticket #417) — neither
  an Aktionsfreigabe nor the Offenlegungsfreigabe of § 4.9 (#423). For
  emit and transfer a GO still bridges the recipient test (#354).
  """
  @spec not_transmitted?(String.t(), [map()]) :: boolean()
  def not_transmitted?("store", remedies) do
    Go.offered(remedies) == nil and Go.offered_offenlegung(remedies) == nil and
      Enum.any?(remedies, &(&1["code"] == "recipient_not_allowed"))
  end

  def not_transmitted?(_rule, _remedies), do: false

  @doc """
  Note for an answer without a result: `:deny`, `:not_transmitted`,
  `:go_refused` or `:go_timeout`.

  `:not_transmitted` applies when a recipient lies outside the recipient
  circle and no GO can change that (ticket #417). The model then only
  learns that nothing was transmitted and gets no prompt towards a
  cleaned-up version: it would offer one in a room as well whose
  non-public content could leak into the wording (Gegenprobe 13.5 in the
  reference scenario).
  """
  @spec text(:deny | :not_transmitted | :go_refused | :go_timeout) :: String.t()
  def text(:deny) do
    "Gesperrt: Dieser Aufruf ist in diesem Arbeitsraum nicht zulässig. " <>
      "Ein anderes Werkzeug oder eine umformulierte Anfrage führt nicht zum Ziel, " <>
      "denn die Sperre hängt am Arbeitsraum, nicht an der Formulierung. " <>
      "Versuche es nicht erneut. Sag der nutzenden Person, was gesperrt ist, " <>
      "und nenne die Schritte aus remedies."
  end

  def text(:not_transmitted) do
    "Nicht übertragen: Nichts aus diesem Aufruf hat den Arbeitsraum verlassen, " <>
      "und kein GO ändert das. Versuche es nicht erneut, auch nicht mit einer " <>
      "gekürzten oder umformulierten Fassung und nicht über ein anderes Werkzeug. " <>
      "Sag der nutzenden Person nur, dass nichts übertragen wurde."
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
