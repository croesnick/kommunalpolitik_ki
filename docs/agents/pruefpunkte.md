# Prüfpunkte je Bereich

Stand: 2026-11-12. Diese Prüfpunkte gelten bei jeder Änderung im jeweiligen Bereich, auch wenn das Ticket sie nicht eigens nennt (#461). Im Prüfbericht ([Lane-Protokoll](lane-protocol.md#prüfbericht-the-verification-report)) bekommt jeder Punkt eines Bereichs, den der Diff berührt, eine eigene Zeile. Die Prüfpunkte eines Tickets unter „Fertig, wenn“ bleiben im Ticket.

Welche Punkte hier stehen, entscheidet die nutzende Person. Jeder Punkt hat ihr GO. Eine Session schlägt neue Punkte vor und trägt sie nicht selbst ein.

## Hub-Oberfläche

**Gilt für:** `apps/ratsprojekte/assets/`, `apps/ratsprojekte/lib/ratsprojekte_web/`

- **Light und Dark, ab Handybreite.** Jede Seite folgt dem Theme und funktioniert ab Handybreite. Feste Farben stehen nur in den beiden Theme-Blöcken und in `@media print`. Ausnahmen gelten für Farben, die in beiden Themes gleich sind und nicht als Fläche oder Text dienen, und sie stehen im Test.
  *Nachweis:* Screenshot jeder geänderten Seite hell und dunkel, eine davon in Handybreite. Automatisch: `apps/ratsprojekte/test/ratsprojekte_web/theme_css_test.exs` (feste Farben in `app.css` und feste Tailwind-Farbklassen in Templates).

## Ratsinhalte

**Gilt für:** das ganze Repo

- **Keine echten Daten.** Tests, Fixtures, Seeds, Kassetten im Repo und Transkripte enthalten keine echten Ratsinhalte und keine echten Personen (AGENTS.md §8). Erfundenes Material spielt in der erfundenen Gartenstadt.
  *Nachweis:* Review

## komki, für Nutzende sichtbar

**Gilt für:** Änderungen an dem, was Nutzende von komki sehen oder tun: Befehle, Optionen, Ausgaben, Einrichtung, Sicherheitsgrenze

- **Doku-Site angepasst.** Derselbe PR passt die betroffenen Seiten unter `docs/site/` an. Terminal-Ausgaben dort stammen aus echten Läufen.
  *Nachweis:* Doku-Diff

## Quellenpflicht

**Gilt für:** Tools, Skills und Connectoren, die politisch relevante Aussagen ausgeben

- **Jede Aussage hat eine Quelle.** Politisch relevante Ausgaben tragen URL, Abrufdatum und, wo es passt, den Paragrafen (AGENTS.md §6).
  *Nachweis:* Test oder echter Lauf

## Neue Prüfpunkte

Was in einem Review oder bei der nutzenden Person durchrutscht, wird als neuer Prüfpunkt vorgeschlagen, möglichst gleich als automatischer Check. Der Vorschlag kommt als Kommentar ins Ticket oder als eigenes Ticket. Er nennt Bereich, Punkt, Nachweisart und den Anlass. Mit dem GO der nutzenden Person kommt er hierher. Lässt sich der Punkt maschinell prüfen, gehört der Test oder CI-Check in denselben PR. Belegt wird der Check mit einem roten Lauf auf dem Fehler, der ihn ausgelöst hat, und einem grünen danach.
