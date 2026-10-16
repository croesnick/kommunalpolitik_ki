---
name: mermaid_vision_loop
description: >
  Mermaid-Diagramme render- und vision-geprüft optimieren: Diagrammquellen
  extrahieren, lokal mit mermaid@11 rendern (gleiche Major-Version wie
  GitHub), im Playwright-Browser screenshoten, vom @observer-Agenten auf
  Übersichtlichkeit bewerten lassen und refaktorieren, bis das Urteil
  „gut lesbar“ steht. Nutze diesen Skill immer, wenn ein Mermaid-Diagramm
  neu entsteht, geändert wird oder als unübersichtlich kritisiert wird — in
  READMEs, docs/, RFCs und ADRs. Typische Trigger: „Mach ein
  Mermaid-Diagramm für …“, „Das Diagramm ist unübersichtlich“,
  „Optimiere das Diagramm“, „Lass das Diagramm bewerten“, „Prüfe die
  Lesbarkeit des Diagramms“.
---

# Mermaid-Vision-Loop

Nicht im Quelltext zeigt sich die Qualität eines Mermaid-Diagramms, sondern
im gerenderten Bild — und dort in der Zielbreite (~980 px Inhaltsspalte auf
GitHub). Dieser Skill macht die visuelle Qualität zu einem geprüften Gate:
Diagramm → Render → Feedback → Refactor → Done, in maximal drei Runden.
Als Ground Truth gilt das echte Browser-Rendering mit derselben
Mermaid-Major-Version wie GitHub; das Urteil fällt der @observer-Agent
(vision-fähig, Kontext bleibt außerhalb der Session).

## Ablauf

### 1. Quellen extrahieren

Zuerst die Mermaid-Blöcke aus der Zieldatei (README, Doc, RFC) in
eigenständige `.mmd`-Dateien in ein Temp-Verzeichnis legen, z. B.
`…/T/opencode/mermaid/`.
Als Editing-Oberfläche des Loops dienen die `.mmd`-Dateien; die Zieldatei
wird erst am Ende synchronisiert (Schritt 8).

Erledigt, wenn: jedes Diagramm als eigene `.mmd`-Datei vorliegt.

### 2. render.html erzeugen

```sh
python3 skills/mermaid_vision_loop/scripts/render_mermaid.py \
  d1.mmd d2.mmd --out <tmp>/render.html
```

Per `json.dumps` bettet das Script die Quellen als JS-Strings ein (kein
HTML-Parsing: `<br/>` bleibt erhalten), kopiert `mermaid.min.js` daneben
(einmaliger Download nach `~/.cache/mermaid-skill/`, danach offline) und
schreibt die Sentinel-Logik (`RENDER-OK` / `RENDER-FAIL`).

Erledigt, wenn: das Script „geschrieben“ meldet.

### 3. Lokalen HTTP-Server starten

Weil der Playwright-MCP `file://`-URLs blockiert, braucht die Seite einen
lokalen Server:

```sh
(nohup python3 -m http.server 8791 --bind 127.0.0.1 >server.log 2>&1 &)
curl -s -o /dev/null -w "%{http_code}\n" http://127.0.0.1:8791/render.html
```

Port frei wählen und die komki-Ports meiden (49524, 49525, 49531,
49721–49723).

Erledigt, wenn: der Status-Code 200 ist.

### 4. Im Playwright-Browser rendern

Zuerst den Viewport auf ~1100×900 setzen (README-typische Breite), zu
`http://127.0.0.1:<port>/render.html` navigieren, dann mit `browser_find`
nach „RENDER“ suchen:

- `RENDER-OK` = alle Diagramme gerendert.
- `RENDER-FAIL` = Mermaid-Syntaxfehler; Meldung lesen, Quelle korrigieren,
  zurück zu Schritt 2.

Harmlos ist der favicon-404 in der Browser-Konsole.

Erledigt, wenn: `RENDER-OK` im DOM steht.

### 5. Screenshot

`browser_take_screenshot` mit `fullPage: true`, `scale: "device"`
(scharfer Text für die Vision-Prüfung) und einem relativen Dateinamen
unter `.playwright-mcp/diagrams-vN.png` — je Runde versioniert (v1, v2 …).
Nur der Workspace und `.playwright-mcp/` sind erlaubte Roots — absolute
Pfade außerhalb verweigert der Playwright-MCP.

Erledigt, wenn: das PNG vorliegt.

### 6. @observer-Bewertung einholen

Den @observer-Agenten mit dem absoluten Pfad zum PNG und den
Bewertungskriterien losschicken (Prompt-Vorlage unten). Verlangt werden:

- Befunde pro Diagramm mit Schweregrad: blocker / störend / kosmetisch
- Vorschläge auf Mermaid-Quelltext-Ebene (umsetzbar ohne Rätselraten)
- finales Urteil pro Diagramm: „gut lesbar, keine Optimierung nötig“
  oder „Optimierung nötig“ mit Begründung

Ab Runde 2 die Observer-Session per `task_id` wiederverwenden und nur einen
Delta-Prompt schicken: was sich geändert hat, was nachgeprüft wird, ob
die Umgestaltung neue Probleme gebracht hat.

Erledigt, wenn: für jedes Diagramm ein Urteil vorliegt.

### 7. Refaktorieren

Nur die beanstandeten Stellen in den `.mmd`-Dateien ändern. Bewährte Hebel:

- Kantenlabels einzeilig und kurz — Details gehören in die Prosa, nicht
  aufs Label.
- Knoten entschlacken (Flags, Methodennamen, Klammern auflösen).
- Subgraphen für Prozess- und Sandbox-Grenzen: eine Box = ein Prozess.
- Deklarationsreihenfolge ändern, wenn das Layout Kreuzungen erzeugt.

Jede Quelländerung braucht einen neuen Render (zurück zu Schritt 2).
Als Loop-Disziplin gelten maximal drei Runden; Abbruch, wenn nur noch
kosmetische Befunde bleiben. Nicht „fixen“: die Umlaut-Ersatzschreibung (ue/ae) mancher
Zieldateien ist bewusster Datei-Stil. Inhaltliche Korrektheit prüft dieser
Skill nicht — Quellenbindung bleibt Aufgabe des Texts drumherum.

Erledigt, wenn: alle Urteile „gut lesbar“ lauten oder das Rundenlimit
erreicht ist.

### 8. Sync und Abschluss

Zum Schluss die finalen `.mmd`-Inhalte zurück in die Zieldatei (nur die
Diagramm-Blöcke ersetzen), neue Prosa durch den humanizer-de-Skill
schicken, committen — und den HTTP-Server stoppen:

```sh
pkill -f "http.server <port>"
```

`.playwright-mcp/` ist gitignored, die Renders müssen nicht aufgeräumt
werden.

Erledigt, wenn: Zieldatei synchron ist, der humanizer-Audit sauber ist
und der Server aus ist.

## Fallen

- `file://` blockiert: Playwright-MCP erlaubt nur HTTP — deshalb der
  Umweg über `python3 -m http.server` auf 127.0.0.1.
- Screenshot-Pfade: nur der Workspace und `.playwright-mcp/` sind
  erlaubte Roots; absolute Temp-Pfade werden verweigert.
- `<br/>` im HTML-Div geht verloren: `<div class="mermaid">` parst den
  Inhalt als HTML, Tags verschwinden. Deshalb bettet das Script die Quellen
  als JS-Strings ein — niemals einen Mermaid-Block von Hand ins HTML kleben.
- Kein mmdc nötig: mermaid-cli würde einen Chromium-Download über
  puppeteer nachziehen; die Script-und-Server-Pipeline nutzt den
  Playwright-Browser, der eh da ist.
- Mermaid-Major-Version zählt: GitHub rendert aktuell mermaid@11 — mit
  derselben Major-Version rendern, sonst weicht das geprüfte Bild von dem
  ab, was GitHub später zeigt.
- Sentinel statt Schlaf: nicht auf Zeit raten — `RENDER-OK` /
  `RENDER-FAIL` ist der Vertrag zwischen Seite und Browser.

## Observer-Prompt (Vorlage)

```text
Analysiere das Bild unter diesem absoluten Pfad mit dem Read-Tool:
<absoluter-pfad-zum-png>

Es zeigt N Mermaid-Diagramme (Rendering mit mermaid@11, Theme default,
weißer Hintergrund, ~980 px Breite), bestimmt für einen GitHub-README.
[Kontext: Was zeigt jedes Diagramm — zwei bis drei Sätze.]

Bewerte NUR die Übersichtlichkeit und Lesbarkeit, nicht die inhaltliche
Korrektheit. Kriterien:
1. Textlesbarkeit: Sind alle Beschriftungen bei Skalierung auf ~980 px
   sicher lesbar? Nichts gestaucht oder abgeschnitten?
2. Kantenführung: Überlappen oder kreuzen Linien Labels oder Knoten?
   Sind Pfeile eindeutig zuordenbar?
3. Layout: Bildverhältnis sinnvoll? Abstände ausreichend? Gedrängt?
4. Visuelle Hierarchie: Erkennt man die zentralen Rollen sofort?
5. (Sequenzdiagramme:) Lebenslinien, Nachrichten, alt/else-Blöcke klar
   getrennt und beschriftet?

Antwortformat:
- Pro Diagramm nummerierte Befunde: Was, Wo, Schweregrad
  (blocker / störend / kosmetisch).
- Pro Diagramm konkrete Vorschläge auf Mermaid-Quelltext-Ebene.
- Pro Diagramm finales Urteil: „gut lesbar, keine Optimierung nötig“
  oder „Optimierung nötig“ mit Begründung.
```
