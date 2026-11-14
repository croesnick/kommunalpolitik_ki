---
komki: patch
---

# Existenz-Orakel an der Grenze geschlossen

Zwei Antwortformen der Vermittler-Grenze verrieten bisher die Existenz
verborgener Inhalte:

- `vault_search` redadierte die ganze Antwort, sobald ein Treffer Labels
  außerhalb von Γ trug — statt ihn still auszulassen. Ein Modell konnte
  so auf verborgene Notizen schließen und ihnen zulässige Treffer
  vergiften. Nicht-Γ-Treffer werden jetzt still verworfen (wie Treffer
  außerhalb B_W), das Einzellesen einer Nicht-Γ-Notiz antwortet wie
  `not-found` — von einer fehlenden Notiz nicht mehr unterscheidbar.
- `admit_document` auf ein existierendes, aber gesperrtes Raumdokument
  antwortete mit dem vollständigen Remedy-Katalog (Labels, Bindungen,
  Lockerungsbefugnisse) — ein aufzählbares Existenz- und Label-Orakel.
  Gesperrte Dokumente antworten jetzt wie unbekannte Objekte.

Das Journal führt in beiden Fällen die wahre Entscheidung weiter: Die
nutzende Person sieht im Audit, dass ein verborgenes Objekt sondiert
wurde; das Modell sieht weder Existenz, Labels noch Katalog.
