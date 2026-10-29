# Kommunalpolitik KI

Werkzeuge für die Stadtratsarbeit: das Ratsinformationssystem lokal durchsuchen, Drucksachen auswerten, Fördermöglichkeiten prüfen, Sitzungsmappen anlegen, Projekte strukturieren, Anträge entwerfen. Gebaut für die Ratsarbeit in der Verwaltungsgemeinschaft Buchloe.

> **Neugierig auf komki, den lokalen KI-Arbeitsraum, der Vertrauliches nicht nach draußen trägt?** Der bebilderte Guide steht unter [croesnick.github.io/kommunalpolitik_ki](https://croesnick.github.io/kommunalpolitik_ki/), der Einstieg ohne Technik unter [Worum es geht](https://croesnick.github.io/kommunalpolitik_ki/komki/worum-es-geht/).

Orchestriert wird alles von [OpenCode](https://opencode.ai). Die KI ruft die CLI-Tools und MCP-Server auf und folgt den Anleitungen aus `skills/`. Antworten stammen aus der lokal synchronisierten RIS-Datenbank, aus den ausgelesenen PDFs, aus dem Obsidian-Vault und aus dem Archiv der Lokalzeitung. Eine maschinenlesbare Schnittstelle wie OParl gibt es am Ratsinformationssystem der Verwaltungsgemeinschaft nicht. Deshalb synchronisiert `ratsinfo` die öffentlichen Seiten in eine lokale SQLite-Datenbank und macht Sitzungen, Drucksachen und Beschlüsse volltextdurchsuchbar.

## Was dieses Setup anders macht

**Quellen statt Behauptungen.** Jede politisch relevante Aussage aus diesen Tools nennt ihre Herkunft: URL, Abrufdatum, Sitzung und TOP oder Paragraf. In den Datenmodellen sind Quellen ein eigener Typ, die Recherche-Skills führen sie mit. Damit ist Belegen in jedes Werkzeug eingebaut.

**Die KI berät, der Mensch entscheidet.** In ratsprojekte kann die KI Projekte nicht direkt ändern. Sie legt Vorschläge an, der Stadtrat nimmt an oder verwirft. Beides ist endgültig und wird protokolliert. Lesezugriffe sind frei, alle Schreibzugriffe laufen durch dieses GO-Gate. Die Entscheidung kann im Chat fallen und dort über das MCP-Werkzeug `decide_proposal` ausgeführt werden, oder gleich im Dashboard.

**Ein Gedächtnis, ein Destillat.** Der Obsidian-Vault ist das rohe Gedächtnis: Notizen, Mails, Artikel, Protokolle. ratsprojekte ist das Destillat: konsolidierte Projekte mit Realisierungssträngen, rechtlichen Vorbedingungen, Quellen und Beschlussvorschlag. Nur in eine Richtung läuft der Fluss, vom Vault nach ratsprojekte, nie zurück. Der Verbindungspunkt ist ein Slug, etwa `#ratsprojekt/marktplatz-umgestalten` im Vault und `/projekte/marktplatz-umgestalten` im Dashboard.

**Alles liegt lokal.** Die Datenbank ist SQLite auf dem eigenen Rechner, Drucksachen liegen als PDF vor Ort, der Vault ist ein lokales Verzeichnis. Zugriffe auf das RIS sind reine Lesezugriffe.

**Der Zustand ist ehrlich dokumentiert.** `docs/workflows.md` ordnet jedes Tool einem der elf Rats-Workflows zu und hält fest, was davon Lücke ist. Der Abschnitt [Grenzen](#grenzen) führt die offenen Stellen auf.

## Aufgaben und Skills

OpenCode lädt die Ablauf-Anleitungen aus `skills/`. Im Chat genügt die Aufgabe, etwa „Bereite die nächste Sitzung vor“.`

- **Sitzung vorbereiten.** `sitzungsvorbereitung` holt die Agenda aus dem RIS, nimmt die Vorlagen-PDFs auseinander, zieht passende Artikel der Allgäuer Zeitung und eigene Vault-Notizen bei und schreibt daraus die Sitzungsmappe als Notiz im Vault. Sie sagt, was drankommt, was zu lesen ist und wo es Querbezüge gibt.
- **Rückblick halten.** `bericht_aus_dem_stadtrat` sammelt die Sitzungen und Notizen seit dem letzten Bericht und verdichtet sie zu einer Notiz für Stammtisch, Fraktionssitzung oder Vorstand.
- **Fördermöglichkeiten prüfen.** `foerdermittel_recherche` recherchiert für ein konkretes Vorhaben, welche Programme infrage kommen, mit Eigenanteilen, Fristen und Kumulierungsregeln. Schwerpunkt Bayern: BayFAG, KommKlimaFöR, Städtebauförderung, SUMP. Jede Angabe mit Quelle.
- **Neue Informationen einordnen.** `ratsprojekt_delta` hält eine Mail, einen Artikel oder eine geänderte Förderrichtlinie gegen den Stand eines Projekts und liefert ein strukturiertes Delta: was sich ändert, welche Quellen dazukommen, ob die Antragsreife steigt. `ratsprojekt_stand` liefert den Ist-Zustand.
- **Projekt anlegen.** `ratsprojekt_proposal` konsolidiert das Material zu einer Vault-Notiz, prüft die Antragsreife-Gates und bringt den Vorschlag in ratsprojekte ein. Ob er angenommen wird, entscheidet der Stadtrat.
- **Antrag entwerfen.** `antrag_generieren` schreibt einen fraktionsneutralen Entwurf, aufbauend auf einer Struktur aus realen Anträgen. Die Vorlage der eigenen Fraktion kommt über den Vault-Tag `#antragsvorlage`. Die KI formuliert, finalisiert wird von Hand.
- **Im Vault suchen.** `vault_suche` durchsucht die eigenen Notizen und liefert Treffer mit Kontext. Read-only.

Daneben laufen die Einzelwerkzeuge direkt: `ratsinfo` für das RIS, `pdf_ingest` für Drucksachen, die AZ- und die ODS-Anbindung für Zeitung und Tabellen. Sie stehen auch ohne Skill im Chat bereit.

## Bausteine

| Baustein | Zweck | Schnittstelle |
|---|---|---|
| `apps/ratsinfo` | RIS synchronisieren, Volltextsuche über Sitzungen, Drucksachen und Beschlüsse, Drucksache im Browser öffnen | CLI |
| `apps/ratsprojekte` | Projekt-Dashboard: Stränge, Vorbedingungen, Quellen, Antragsreife | LiveView und MCP |
| `apps/komki_cli` | lokal gesandboxter AI-Arbeitsraum für macOS: Modell nur auf Loopback, Seatbelt-Profil, Boot-Gate vor jedem Start | CLI |
| `apps/komki_policy` | rechnet aus, ob eine Absicht nach den Regeln zulässig ist, und prüft die Begründung nach; führt selbst nichts aus | CLI |
| `apps/shared` | gemeinsame Domain-Models der Elixir-Apps | Bibliothek |
| `tools/allgaeuer_zeitung_mcp` | Allgäuer Zeitung durchsuchen und Artikel lesen | MCP |
| `tools/pdf_ingest` | PDF-Text und Markierungen extrahieren; OCR nur für gescannte PDFs | MCP |
| `tools/nextcloud_ods_mcp` | ODS-Tabellen lesen: Blätter, Bereiche, Zellen, Suche | MCP |
| Nextcloud-MCP (extern) | Nextcloud-Dateien, Kalender, Notizen, Deck | MCP |

KomKI ist der Baustein für AI-Arbeit ohne Cloud. Das Modell läuft ausschließlich auf dem Loopback-Interface. Vor jedem Lauf verlangt ein Boot-Gate die Bestätigung, und ein Seatbelt-Profil begrenzt Datei- und Netzwerkzugriffe. Modell, llama.cpp und Coding-Agent sind gepinnt, der Download wird per SHA-256 geprüft. `komki_policy` gehört dazu und bleibt rein rechnend: Es entscheidet, ob eine Absicht zulässig ist, und verifiziert die Begründung, führt aber selbst nichts aus.

## Verzeichnisse

`apps/` enthält die Elixir-Apps, `tools/` die Python-Werkzeuge, `skills/` die Ablauf-Anleitungen für OpenCode und `docs/` die kanonische Dokumentation. Prinzipien, Guardrails und Tooling-Vorgaben stehen vollständig in [AGENTS.md](AGENTS.md).

## Einrichten

Vorausgesetzt werden Elixir, `uv` für die Python-Werkzeuge und SQLite. Für die Vault-Workflows braucht es den `obsidian` CLI und eine laufende Obsidian-App. Alle externen Abhängigkeiten mit Installationswegen und Fallbacks stehen in [docs/prerequisites.md](docs/prerequisites.md).

```bash
# einmalig pro Clone: Secret-Scan vor jedem Commit
brew install gitleaks pre-commit
pre-commit install

# Elixir-Workspace und ratsprojekte
mix deps.get
cd apps/ratsprojekte
mix ecto.migrate
mix phx.server   # Dashboard unter http://localhost:4000, MCP-Endpoint /mcp

# ratsinfo systemweit (braucht ggf. sudo, Alternativen siehe Makefile)
make install

# Python-Werkzeuge
make deps
```

Das Repo liefert keine Beispielprojekte für ratsprojekte. Wer lokal einen Seed-Datensatz hat, spielt ihn mit `mix run priv/repo/seeds.exs` ein.

Zugangsdaten für die Allgäuer Zeitung und Nextcloud liegen in den Umgebungsvariablen `AZ_EMAIL` und `AZ_PASSWORD` beziehungsweise `NEXTCLOUD_HOST`, `NEXTCLOUD_USERNAME` und `NEXTCLOUD_PASSWORD`. `opencode.json` gibt die Server-Verkabelung vor. Für AZ-Artikel ist einmalig `uv run playwright install chromium` nötig, für gescannte PDFs OCRmyPDF mit deutschem Tesseract (`brew install ocrmypdf`).

Ohne laufenden `obsidian` CLI legen die Vault-Skills ihre Notizen unter `artifacts/vault-staging/` ab. Das Kopieren in den Vault ist dann Handarbeit.

## Grenzen

- Beschlussnachverfolgung fehlt. ratsprojekte verknüpft Projekte nicht mit RIS-Sitzungen und trackt keine Fristen. Die Issues #32 bis #34 sammeln, was dafür gebraucht wird.
- Öffentlichkeitsarbeit hat kein Werkzeug. Für Presse, Newsletter und kanalgebundene Texte liegen keine Vorlagen vor.
- Der Lebenszyklus ist teils Spezifikation. Im Code erzwungen ist die Proposal-Entscheidung. Die übrigen Statusübergänge verlassen sich bislang auf die Disziplin der Skills, nicht auf Guards. Details: [docs/ratsprojekte-lifecycle.md](docs/ratsprojekte-lifecycle.md).
- Zwei MCP-Server sind nicht eingebunden. `obsidian_mcp` und `ratsinfo_mcp` liegen im Repo, `opencode.json` nutzt sie nicht. Der Vault-Zugriff läuft über den `obsidian` CLI.
- Zwei Antragsreife-Gates sind noch Richtlinie. Value Proposition und Success Metrics prüfen vorerst die Skills, Felder in ratsprojekte folgen mit Issue #37.

## Doku und Verweise

- [AGENTS.md](AGENTS.md) benennt Prinzipien, Architektur, Guardrails und Tooling-Vorgaben.
- [docs/workflows.md](docs/workflows.md) ordnet die elf Rats-Workflows ihren Tools zu und führt die Lücken auf.
- [GLOSSARY.md](GLOSSARY.md) definiert die kanonischen Fachbegriffe des Repos.
- [docs/ratsprojekte-lifecycle.md](docs/ratsprojekte-lifecycle.md) beschreibt Status, Übergänge und Gates.
- [docs/prerequisites.md](docs/prerequisites.md) listet externe Abhängigkeiten mit Installation und Fallbacks.
- [GitHub Projects](https://github.com/users/croesnick/projects) sammelt Issues, Meilensteine und Priorisierung.

## Lizenz

MIT, siehe [LICENSE](LICENSE).
