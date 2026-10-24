# Doku-Site „komki“ (Astro Starlight)

Der bebilderte Benutzer-Guide zu komki, veröffentlicht über GitHub Pages unter
`https://croesnick.github.io/kommunalpolitik_ki/`. Er zeigt, wie man komki benutzt; die Begründungen stehen
weiter in den RFCs und im [Entscheidungshandbuch](../research/2026-10-20-tool-zugang-entscheidungshandbuch.md).
Warum Starlight: [Report Doku-Site und Bildband](../research/2026-10-24-doku-site-und-bildband.md).

## Lokal ansehen

```sh
cd docs/site
npm ci
npm run dev        # http://localhost:4321/kommunalpolitik_ki/ mit Live-Reload
npm run build      # erzeugt dist/ wie in CI
```

## Eine Seite schreiben

- Seiten liegen unter `src/content/docs/` als `.mdx` (Markdown plus Starlight-Komponenten wie
  `<Steps>`, `<Aside>`, `<Card>`). Die Seitenleiste steht in `astro.config.mjs`.
- Interne Links schreiben wir mit Basis-Pfad: `/kommunalpolitik_ki/komki/in-betrieb-nehmen/`.
- Terminal-Ausgaben als Codeblock mit `frame="terminal" title="Das siehst du"`. Nur echte Ausgaben aus einem
  Lauf übernehmen; Pfade generisch mit `~` schreiben.
- Diagramme als SVG unter `src/assets/`, eingebunden als Komponente
  (`import Bild from '../../assets/bild.svg'` und `<div class="komki-figure"><Bild /></div>`). Farben nur über die
  Klassen aus `src/styles/komki.css`, dann folgen sie dem Hell/Dunkel-Umschalter.
- Keine externen Schriften oder Skripte (Datenschutz bei öffentlicher Auslieferung).
- Terminal-Screenshots entstehen mit dem Skill [`terminal_screenshot`](../../skills/terminal_screenshot/SKILL.md)
  aus einer echten Sitzung, nie als Nachbau.

## Gestaltung

Gewählt am 24.10.2026 aus einem Katalog von zwölf Richtungen: „Leicht lesbar“, ruhig, freundlich und seriös.

- Schriften: Zilla Slab für Überschriften, Atkinson Hyperlegible Next für den Text, Atkinson Hyperlegible Mono für
  Code. Alle drei liegen selbst gehostet über Fontsource bei (SIL Open Font License) und sind in
  `astro.config.mjs` eingebunden.
- Eine Akzentfarbe, ein ruhiges Blau. Sie markiert, was klickbar ist oder gliedert. Alle Farben stehen als
  Variablen oben in `src/styles/komki.css`, je einmal für dunkel und hell.
- Hervorgehoben wird über Größe und Gewicht der Schrift. Keine Textmarker, keine Deko-Symbole, keine
  verspielten Themen-Elemente.

## Veröffentlichen

`.github/workflows/pages.yml` baut die Site in jedem Pull Request (Prüfung) und veröffentlicht sie bei jedem Push
auf `main`. Voraussetzung: GitHub Pages steht in den Repo-Einstellungen auf „GitHub Actions“.
