# Prüfpunkte je Bereich

Stand: 2026-11-14. Diese Prüfpunkte gelten bei jeder Änderung im jeweiligen Bereich, auch wenn das Ticket sie nicht eigens nennt (#461). Im Prüfbericht ([Lane-Protokoll](lane-protocol.md#prüfbericht-the-verification-report)) bekommt jeder Punkt eines Bereichs, den der Diff berührt, eine eigene Zeile. Die Prüfpunkte eines Tickets unter „Fertig, wenn“ bleiben im Ticket.

Ein Punkt gilt für den Diff: Er fragt, was die Änderung einbringt, nicht ob das ganze Repo ihn schon erfüllt. Altbestand, der einen Punkt verletzt, steht beim Punkt mit seinem Folgeticket.

Welche Punkte hier stehen, entscheidet die nutzende Person. Jeder Punkt hat ihr GO, ebenso jede Ausnahme in einem automatischen Check. Eine Session schlägt neue Punkte und Ausnahmen vor und trägt sie nicht selbst ein.

## Hub-Oberfläche

**Gilt für:** `apps/ratsprojekte/assets/`, `apps/ratsprojekte/lib/ratsprojekte_web/`, `apps/ratsprojekte/test/ratsprojekte_web/theme_css_test.exs`

- **Light und Dark, ab Handybreite.** Jede geänderte Seite folgt dem Theme und funktioniert ab Handybreite. Der Diff bringt feste Farben nur in die beiden Theme-Blöcke und in `@media print` ein. Ausnahmen mit GO: die Datenfarben der Meinungsbalken (`--stufe-1` bis `--stufe-5` auf `:root`, in beiden Themes gleich) und Schatten mit höchstens 30 % Deckkraft.
  *Nachweis:* Screenshot jeder geänderten Seite hell und dunkel, eine davon in Handybreite, erzeugt mit dem Screenshot-Werkzeug aus `make screenshot-install` ([interaktive-sessions.md](interaktive-sessions.md#screenshots-der-hub-oberfläche)), im Dev-Loop über `.dev-loop/screenshots.json`. Zustände während einer Navigation nimmt `--navigate` auf. Automatisch: `apps/ratsprojekte/test/ratsprojekte_web/theme_css_test.exs` (feste Farben in `app.css` und `assets/js/app.js`, feste Farbklassen und Inline-Farben in Templates).

## Ratsinhalte

**Gilt für:** das ganze Repo

- **Keine echten Daten.** Der Diff bringt keine echten Ratsinhalte in Tests, Fixtures, Seeds oder Transkripte ein (AGENTS.md §8).
  *Nachweis:* Review
  *Altbestand:* Einige Fixtures nennen noch Buchloe, etwa in `apps/komki_cli/test/pi/fixtures/`. Die Umstellung auf die Gartenstadt ist Stufe B19 im [Szenario](../szenarien/radweg-bahnhofstrasse.md).

## komki, für Nutzende sichtbar

**Gilt für:** Änderungen an dem, was Nutzende von komki sehen oder tun: Befehle, Optionen, Ausgaben, Einrichtung, Sicherheitsgrenze

- **Doku-Site angepasst.** Derselbe PR passt die betroffenen Seiten unter `docs/site/` an. Terminal-Ausgaben dort stammen aus echten Läufen.
  *Nachweis:* Doku-Diff

## Einheiten mit Version

**Gilt für:** `lib/` und `priv/` der Einheiten aus `knope.toml` (`apps/komki_cli`, `apps/ratsprojekte`, `apps/sidecar`, `apps/seatbelt`, `apps/sealed_envelope`) und der Apps, die sie mitbringen: zu komki gehören Vermittler, Policy, Connectoren und Egress ([changesets.md](changesets.md#einheiten))

- **Changeset passt.** Merken Nutzende einer Einheit die Änderung, bringt der Diff ein Changeset unter `.changeset/` mit, das die Einheit nennt, aus Sicht ihrer Leser geschrieben ist (komki und ratsprojekte deutsch für Nutzende, die Bibliotheken englisch für Entwickler) und eine passende Stufe trägt ([changesets.md](changesets.md)). Sonst trägt der PR das Label `ohne-changeset`, und der Prüfbericht begründet, warum Nutzende nichts merken.
  *Nachweis:* Review des Changesets. Automatisch: Workflow `changesets` (`elixir scripts/changesets.exs check origin/main`) prüft, dass jede berührte Einheit genannt ist und knope das Changeset lesen kann. Ob der Text passt, prüft nur das Review.

## Quellenpflicht

**Gilt für:** Tools, Skills und Connectoren, die politisch relevante Aussagen ausgeben

- **Jede Aussage hat eine Quelle.** Politisch relevante Ausgaben tragen URL, Abrufdatum und, wo es passt, den Paragrafen (AGENTS.md §6).
  *Nachweis:* Test oder echter Lauf

## Neue Prüfpunkte

Was in einem Review oder bei der nutzenden Person durchrutscht, wird als neuer Prüfpunkt vorgeschlagen, möglichst gleich als automatischer Check. Der Vorschlag kommt als Kommentar ins Ticket oder als eigenes Ticket. Er nennt Bereich, Punkt, Nachweisart und den Anlass. Mit dem GO der nutzenden Person kommt er hierher. Lässt sich der Punkt maschinell prüfen, gehört der Test oder CI-Check in denselben PR. Belegt wird der Check mit einem roten Lauf auf dem Fehler, der ihn ausgelöst hat, und einem grünen danach.
