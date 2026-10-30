---
status: accepted
---

# Connectoren nur in Elixir, fehlende Bibliotheken bauen wir selbst

Mehrere Quellen haben ihre beste Bibliothek nur in Python: PyMuPDF für PDF-Text mit Seitenankern, Annotationen und OCR, trafilatura für die Artikel-Extraktion, Playwright für den Paywall-Login der Allgäuer Zeitung. Ticket #278 hat drei Wege abgewogen: ein Elixir-Connector startet ein gepinntes Python-CLI als Kindprozess, ein Connector wird komplett in Python geschrieben, oder Connectoren bleiben Elixir. Wir bleiben bei Elixir. Fehlt eine Bibliothek, bauen wir sie selbst und geben sie als eigenständiges Paket an die Elixir-Community zurück, wie bei `apps/sidecar` (#225) und `apps/seatbelt` (#226). Bis eine Bibliothek fertig ist, hat ein Connector weniger Funktionen, zum Beispiel PDF-Text ohne OCR.

Von Elixir weicht ein Connector nur aus starken Gründen ab, und jede Abweichung braucht vorher die Zustimmung der nutzenden Person. Dass es in Python eine fertige Bibliothek gibt, ist für sich noch kein starker Grund. Ein Grund ist stark, wenn eine Bibliothek in Elixir mit vertretbarem Aufwand nicht zu bauen ist, etwa eine ausgewachsene Browser-Engine. Die Abwägung kommt als Vorschlag ins Ticket, und erst nach dem GO wird gebaut.

**Nativer Code gilt als Elixir, solange die Schnittstelle Elixir ist.** Müssen wir nativen Code einbinden oder selbst bauen, etwa einen NIF in Rust über Rustler, ist das ausdrücklich in Ordnung und keine Abweichung. Ein vorkompilierter NIF aus einem Hex-Paket zählt ebenso, zum Beispiel `ex_pdfium`. Entscheidend ist, dass der Connector und andere Aufrufer nur eine Elixir-API sehen. Nur wenn gute Gründe gegen eine Elixir-Schnittstelle sprechen, gilt die Abweichungsregel oben.

## Begründung

- **Eine Laufzeit an der Sicherheitsgrenze.** Profile, Start und Programm-Pins setzen heute ein Escript voraus (`apps/seatbelt`, `apps/komki_connector/CONTRACT.md` §4/§5). Ein Python-Kind erbt das Profil des Connectors, weil Seatbelt sich nicht verschachteln lässt. Das Profil müsste dann den Interpreter samt `site-packages` freigeben, und der Pin müsste Interpreter, Lockfile und native Wheels umfassen. Ein Connector komplett in Python bräuchte außerdem ein zweites Frame-Protokoll und eine zweite Profil-Grundschicht, die beide synchron gehalten werden müssten.
- **Lizenz.** PyMuPDF steht unter AGPL-3.0. Eine eigene Elixir-Bibliothek kann eine permissive Lizenz bekommen.
- **Der Community etwas zurückgeben** ist ein erklärtes Ziel von komki. Jede fehlende Bibliothek ist ein Kandidat dafür.

## Folgen

- **Pins und Profile** kommen ohne Python aus: keine Interpreter-Pfade im Profil, kein Lockfile im Pin. Ein Connector in reinem Elixir bleibt ein Escript.
- **Ein Connector mit NIF braucht eine zweite Programmform.** Ein Escript kann keinen NIF laden. `priv/` steckt im Archiv, und `dlopen` scheitert mit `errno=20`, auch ohne Sandbox (Probe in #278). Als Mix-Release lief derselbe Connector unter einem Profil aus `Seatbelt.Escript.runtime/2`. Dafür war eine zusätzliche Release-Schicht nötig: die Werkzeuge des Start-Skripts sowie Ausführen und Laden nativer Bibliotheken in der Release-Wurzel. Welche Form es wird, entscheidet ein Folgeticket. Der Vorschlag ist eine Burrito-Einzeldatei: Die Burrito-Schicht gibt es schon für komki selbst, und der Pin bleibt eine einzelne Datei.
- **`tools/pdf_ingest` und `tools/allgaeuer_zeitung_mcp`** bleiben vorerst Werkzeuge außerhalb von komki. Als Connector kommen sie nur in Elixir in den Arbeitsraum. Der Dokument-Connector (#160, #198) startet mit dem Funktionsumfang, den Elixir heute hergibt.
- **Für jede fehlende Bibliothek** gibt es ein eigenes Ticket mit Kandidat, Schnittstelle und Abgrenzung. Generalisierte Pakete schreiben wir auf Englisch.
- **Prototyp-Beleg (#278):** Die Elixir-Connectoren `web`, `vault`, `documents` und `ris` laufen bereits unter echten Seatbelt-Profilen. Die gewählte Option braucht deshalb keinen neuen Wegwerf-Prototyp. Ob die einzelnen Bibliotheken in Elixir machbar sind, klären die Folgetickets.
- **PDF-Kandidat:** `ex_pdfium` 0.6.0 (MIT, pdfium über Rust) liefert in der Probe den Text pro Seite und die Highlights mit Kommentar und Rechteck. Den markierten Text liefert der Schnitt der Zeichenpositionen mit dem Rechteck. Die QuadPoints werden nicht ausgelesen, OCR fehlt.
- **AGENTS.md, Prinzip 1** wird verschärft: PyMuPDF, trafilatura und Playwright gelten nicht mehr von selbst als „prinzipielles Dagegen“. Jede Abweichung wird mit der nutzenden Person abgestimmt. Nativer Code hinter einer Elixir-Schnittstelle ist keine Abweichung.
