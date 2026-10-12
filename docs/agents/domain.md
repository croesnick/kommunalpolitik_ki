# Domain Docs

Wie die Engineering-Skills die Domain-Dokumentation dieses Repos lesen, bevor sie den Code erkunden.

## Before exploring, read these

- `GLOSSARY.md` am Repo-Root: Begriffe der Software-Domäne. Existiert noch nicht — wird lazily von `/domain-modeling` (via `/grill-with-docs`, `/improve-codebase-architecture`) angelegt, sobald Begriffe erstmals festgezurrt werden.
- `docs/adr/`: Architektur-Entscheidungen zum Arbeitsgebiet. Existiert noch nicht — gleiche Lazy-Regel.
- `docs/nomenklatur.md`: Fachbegriffe der Ratsarbeit (Sitzungsmappe, Ratsprojekt, Vault & Co.) — die übergeordnete Referenz. Wer einen dieser Begriffe benutzt, folgt dortiger Definition.
- `docs/ratsprojekte-lifecycle.md`: Single Source of Truth für den Projektlebenszyklus (Statuswerte, Übergänge, Gates) — Workflow-Änderungen aktualisieren zuerst dieses Dokument (AGENTS.md, Prinzip 11).

Existiert eine der Lazy-Dateien nicht: **stillschweigend weiterarbeiten**, das Fehlen nicht monieren, nichts vorbeugend anlegen.

## File structure

Single-Context (dieses Repo):

```
/
├── GLOSSARY.md          ← lazy
├── docs/
│   ├── adr/             ← lazy
│   ├── agents/          ← diese Dateien
│   ├── nomenklatur.md
│   └── ratsprojekte-lifecycle.md
```

## Glossar-Vokabular benutzen

Wenn dein Output einen Domänenbegriff benennt (Issue-Titel, Refactor-Vorschlag, Hypothese, Testname), benutze ihn so, wie `GLOSSARY.md` ihn definiert — für Ratsarbeit-Begriffe so, wie `docs/nomenklatur.md` sie definiert. Keine Synonyme, die das Glossar vermeidet.

Fehlt ein Begriff: entweder erfindest du Sprache, die das Projekt nicht benutzt (überdenken) — oder es gibt eine echte Lücke (für `/domain-modeling` vormerken).

## ADR-Konflikte kenntlich machen

Widerspricht dein Output einer bestehenden ADR, sag das explizit, statt stillschweigend zu überschreiben:

> _Widerspricht ADR-0007 (…), aber wieder öffnen lohnt sich, weil…_
