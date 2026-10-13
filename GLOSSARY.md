# Kommunalpolitik KI

Werkzeuge für die Stadtratsarbeit: RIS durchsuchen, PDFs verarbeiten, Fördermittel recherchieren, lokale Zeitung lesen. Diese Datei klärt die Begriffe, die in Tickets, Skills und Doku dieses Repos eindeutig sein müssen.

## Language

### Release

**Release**:
Ein GitHub-Release pro Tool, getaggt `<tool>-v<semver>` (z. B. `komki-v0.1.0`). Nur Tools mit verteilbarer Binary sind release-fähig; Apps ohne Binary reifen über Issues und Merges.
_Avoid_: repo-weites Release, Gesamtversion

**Verify-then-Publish**:
Protokoll, dass genau die Datei, die veröffentlicht werden soll, aus dem finalen Commit gebaut, frisch entpackt und gegen die Smoke-Matrix verifiziert wird — nie eine andere Datei als die freigegebene.

**Publish-GO**:
Das einzige GO im Release-Ablauf: Nach vorgelegter Evidenz (Smoke-Protokoll, SHA256SUMS, Notes, Zweit-Maschinen-Check) deckt es Tag-Setzen und Veröffentlichen in einem Zug ab.
_Avoid_: verkettete Teil-GOs

**Smoke-Matrix**:
Die festgelegte Abfolge von Prüfschritten, die eine Release-Binary ohne lokale Entwicklungsumgebung bestehen muss. Für komki konkret im Pilot-Bericht festgeschrieben.

**Payload-Staleness**:
Der Effekt, dass eine neu gebaute Binary derselben Version beim Start den bereits entpackten alten Nutzdatensatz weiternutzt statt den neuen zu entpacken. Grund für die Uninstall-Pflicht vor jedem Test einer gleichversionigen Rebuild-Binary.

**Dual-Artefakt-Disziplin**:
Vereinbarung, dass beide komki-Artefakte — Escript (Entwicklungsweg) und Burrito-Binary (Verteilung) — jederzeit funktionsfähig bleiben müssen.
