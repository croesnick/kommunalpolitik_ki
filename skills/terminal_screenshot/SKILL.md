---
name: terminal_screenshot
description: >
  Terminal-Screenshot für READMEs und Doku erzeugen: eine echte TUI-/CLI-Sitzung
  in tmux mit Farben capturen, als SVG rendern, im Browser verifizieren und in
  die README einbetten. Nutze diesen Skill immer, wenn ein README oder eine Doku
  ein Nutzungsbild eines CLI-Tools braucht. Typische Trigger: „Mach einen
  Screenshot von komki für die README", „Zeig, wie eine Session aussieht",
  „Die README braucht ein Bild von der Nutzung", „Dokumentiere Tool X mit einem
  Beispiel-Screenshot". Liefert ein SVG (kein GUI-Bildschirmfoto), das jeder
  Browser korrekt darstellt.
---

# Terminal-Screenshot Skill

Screenshots von Terminal-Tools entstehen hier als **echter Capture einer
laufenden Sitzung**, nicht als Nachbau: tmux-Pane mit ANSI-Farben sichern, mit
`scripts/render_terminal_svg.py` in ein Terminal-SVG mit macOS-Fensterrahmen
wandeln, per Browser-Render verifizieren, einbetten. Beispiel-Output:
[`apps/komki_cli/assets/session-beispiel.svg`](../../apps/komki_cli/assets/session-beispiel.svg).

## Ablauf

### 1. Zielgröße vor dem Session-Start setzen

TUI-Programme frieren ihren Viewport beim Boot ein — pi reagiert auf kein
späteres `resize-window`, der Resize erzeugt nur Leerraum unter dem Footer.
Deshalb steht die Größe *vor* dem Start:

```sh
tmux new-session -d -s keeper            # hält den Server am Leben
tmux set-option -g default-size 112x64   # gilt für die nächste Session
<tool> session --detach                  # jetzt erst starten
tmux display-message -t <session> -p '#{window_width}x#{window_height}'  # muss 112x64 sein
```

**Erledigt, wenn**: die Fenstergröße stimmt, bevor das TUI bootet.

### 2. Eingabe senden und Abschluss abwarten

```sh
tmux send-keys -t <session> -l "<Prompt>"
tmux send-keys -t <session> Enter
```

Dann die Pane pollen, bis die Antwort vollständig ist: kein `Working`-Spinner
mehr, der Inhalt stabil über zwei Captures hinweg.

**Erledigt, wenn**: Prompt, Werkzeufruf (z.B. `write …`) und Antwort im
sichtbaren Bereich liegen. Passt es nicht: Größe bei Schritt 1 erhöhen, Session
neu starten — nachträglich vergrößern funktioniert nicht.

### 3. Capture mit Farben sichern

```sh
tmux capture-pane -t <session> -p -e > capture.txt
```

**Erledigt, wenn**: die Datei Prompt und Footer enthält (Scrollback beginnt in
TUI-Screens am sichtbaren Rand — Früheres ist weg, also vor dem Senden prüfen,
dass alles auf einen Screen passt).

### 4. Rendern und auf Text- und Farbtreue prüfen

```sh
python3 scripts/render_terminal_svg.py capture.txt out.svg "Fenstertitel"
python3 scripts/check_svg_fidelity.py capture.txt out.svg
```

Der Renderer arbeitet zeichenweise mit absoluten x-Koordinaten (8.1px-Raster
bei 13.5px Font) — dadurch ist das Layout von den Font-Metriken des Betrachters
unabhängig. Leerraum-Runs über 4 Zeilen werden auf 2 gecroppt (leerer
Screen-Bereich, kein Inhalt), Reverse-Spaces (Eingabecursor) werden als
Cursor-Block gezeichnet. Der Check liest das SVG strukturell per XML-Parser
(kein Regex) und vergleicht Zeichen, Farben (fill), Bold/Dim-Marker und
Cursor-Blöcke gegen den Capture. Die Bereinigungslogik importiert er direkt
aus dem Renderer. Eine zweite Fassung dieser Logik, die auseinanderdriften
kann, gibt es nicht mehr.

**Erledigt, wenn**: der Fidelity-Check `FIDELITY OK` meldet.

### 5. Im Browser verifizieren

Ground Truth ist das Browser-Rendering — so zeigt das Bild später auch GitHub:

```sh
"/Applications/Google Chrome.app/Contents/MacOS/Chromium" \
  --headless=new --disable-gpu --hide-scrollbars \
  --screenshot=render.png --window-size=<W>,<H> file://<pfad>/out.svg
```

(Das Binary heißt im Chrome.app-Bundle `Chromium`.) Für die visuelle Endabnahme
kann der @observer das PNG prüfen (Layout, abgeschnittene Zeilen, Artefakte).

**Erledigt, wenn**: das Browser-PNG alle Zeilen vollständig zeigt —
insbesondere die längste Zeile und den Footer.

### 6. Einbetten

Relativer Pfad in die README, aussagekräftiger Alt-Text, neue Prosa durch den
humanizer-de-Skill. Aussagen über das Bild müssen zum Bildinhalt stimmen
(Claim-Lock).

**Erledigt, wenn**: README-Text und Bildinhalt zusammenpassen und der
humanizer-Audit für den neuen Abschnitt sauber ist.

## tmux-Fallen

- Server ohne Sessions tot: `kill-session` auf die letzte Session beendet
  den Server; ein Folgendes `set-option` läuft in „no server running“. Eine
  Keeper-Session halten, bis alles fertig ist, dann alles schließen.
- `default-size` zurücksetzen (`tmux set-option -gu default-size`) — die
  globale Option überlebt die Demo sonst.
- Eine komki-Session gleichzeitig: läuft schon eine, verweigert `komki
  session` ohne `--detach` (attach_or_refuse). Für Wegwerf-Sessions:
  `tmux kill-session -t komki`.
- `/exit` kann als Chat durchgehen: Das Modell interpretiert den Befehl als
  Abschiedsnachricht statt das TUI zu beenden. Session-Ende über `kill-session`
  ist zuverlässiger.
- Session-Verläufe: Demo-Sessions landen als neueste unter `pi-home/sessions`
  und können bei `session --continue` die vorherige Arbeitssession verdrängen.
  Nebenwirkung beim Nutzer erwähnen.

## Verifikations-Falle QuickLook

`qlmanage` ignoriert die zeichenweisen x-Koordinaten und fließt Text in der
eigenen Font-Metrik — lange Zeilen *erscheinen* abgeschnitten, obwohl der
Browser sie korrekt zeigt. Auf QuickLook-PNGs kein Urteil stützen; nur das
Chrome-Rendering ist für die Einbettung verbindlich. Der Canvas ist deshalb
mit Sicherheitsreserve gerechnet (Spalten × 9.2 px), damit auch fließende
Renderer nichts verlieren.
