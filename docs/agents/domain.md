# Domain Docs

Wie die Engineering-Skills die Domain-Dokumentation dieses Repos lesen, bevor sie den Code erkunden.

## Before exploring, read these

- `GLOSSARY.md` am Repo-Root: kanonische Nomenklatur aller Domänen — Ratsarbeit (Sitzungsmappe, Ratsprojekt, Vault & Co.) und Software-Domäne. Angelegt aus der früheren `docs/nomenklatur.md`.
- `docs/adr/`: Architektur-Entscheidungen zum Arbeitsgebiet. Existiert noch nicht — gleiche Lazy-Regel.
- `docs/sprachinventur.md`: Inventur der Begriffe — Klassifikation, Quellenbelege und Entscheidungen; das Arbeits- und Belegwerk hinter `GLOSSARY.md`.
- `docs/ratsprojekte-lifecycle.md`: Single Source of Truth für den Projektlebenszyklus (Statuswerte, Übergänge, Gates) — Workflow-Änderungen aktualisieren zuerst dieses Dokument (AGENTS.md, Prinzip 11).

Existiert eine der Lazy-Dateien nicht: **stillschweigend weiterarbeiten**, das Fehlen nicht monieren, nichts vorbeugend anlegen.

## File structure

Single-Context (dieses Repo):

```
/
├── GLOSSARY.md          ← kanonische Nomenklatur
├── docs/
│   ├── adr/             ← lazy
│   ├── agents/          ← diese Dateien
│   └── ratsprojekte-lifecycle.md
```

## Glossar-Vokabular benutzen

Wenn dein Output einen Domänenbegriff benennt (Issue-Titel, Refactor-Vorschlag, Hypothese, Testname), benutze ihn so, wie `GLOSSARY.md` ihn definiert. Keine Synonyme, die das Glossar vermeidet.

Fehlt ein Begriff: entweder erfindest du Sprache, die das Projekt nicht benutzt (überdenken) — oder es gibt eine echte Lücke (für `/domain-modeling` vormerken).

## ADR-Konflikte kenntlich machen

Widerspricht dein Output einer bestehenden ADR, sag das explizit, statt stillschweigend zu überschreiben:

> _Widerspricht ADR-0007 (…), aber wieder öffnen lohnt sich, weil…_
