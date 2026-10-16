#!/usr/bin/env python3
"""Erzeugt render.html aus .mmd-Dateien fuer den Mermaid-Vision-Loop.

Liest beliebig viele Mermaid-Quelltexte (.mmd) und schreibt eine
HTML-Seite, die alle Diagramme untereinander mit mermaid@11 rendert
(dieselbe Major-Version wie GitHub). Die Quellen werden per json.dumps
in JS-Strings eingebettet -- <br/> und Sonderzeichen bleiben intakt,
weil sie nie als HTML geparst werden. Nach erfolgreichem Rendern steht
der Sentinel RENDER-OK im DOM (bei Parse-Fehlern RENDER-FAIL samt
Meldung) -- der Playwright-Browser wartet auf genau dieses Token
statt auf Zeit zu raten.

mermaid.min.js wird einmalig nach ~/.cache/mermaid-skill/ geladen und
in das Ausgabeverzeichnis kopiert; die Seite laeuft damit komplett
offline ueber einen lokalen HTTP-Server (file:// blockiert der
Playwright-MCP, deshalb der Umweg).
"""

import argparse
import json
import shutil
import sys
import urllib.request
from pathlib import Path

MERMAID_URL = "https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.min.js"
CACHE = Path.home() / ".cache" / "mermaid-skill" / "mermaid.min.js"
MIN_BYTES = 100_000  # ein 404-Body ist kleiner als echtes mermaid

TEMPLATE = """<!DOCTYPE html>
<html lang="de">
<head>
<meta charset="utf-8">
<title>Mermaid-Render</title>
<script src="mermaid.min.js"></script>
<style>
  body { background: #ffffff; font-family: -apple-system, sans-serif;
         margin: 24px; }
  h2 { font-size: 18px; color: #333; margin: 24px 0 8px 0; }
  .wrap { max-width: 980px; }
  svg { max-width: 100%; height: auto; }
</style>
</head>
<body>
<div class="wrap">
__SECTIONS__
</div>
<script>
const SOURCES = __SOURCES__;
mermaid.initialize({ startOnLoad: false, theme: "default" });
(async () => {
  try {
    for (const [id, src] of SOURCES) {
      const { svg } = await mermaid.render(id + "-svg", src);
      document.getElementById(id).innerHTML = svg;
    }
    const done = document.createElement("div");
    done.id = "done";
    done.textContent = "RENDER-OK";
    document.body.appendChild(done);
  } catch (e) {
    const err = document.createElement("pre");
    err.textContent = "RENDER-FAIL: " + String(e);
    document.body.appendChild(err);
  }
})();
</script>
</body>
</html>
"""

SECTION = """<h2>__CAPTION__</h2>
<div id="d__N__"></div>"""


def ensure_mermaid() -> Path:
    """Stellt mermaid.min.js im Cache bereit (einmaliger Download)."""
    if not CACHE.exists() or CACHE.stat().st_size < MIN_BYTES:
        CACHE.parent.mkdir(parents=True, exist_ok=True)
        print(f"lade {MERMAID_URL}")
        urllib.request.urlretrieve(MERMAID_URL, CACHE)
        if CACHE.stat().st_size < MIN_BYTES:
            raise SystemExit(
                "mermaid.min.js verdächtig klein -- Download fehlgeschlagen?"
            )
    return CACHE


def build_html(paths: list[Path]) -> str:
    """Baut die HTML-Seite aus den .mmd-Quelltexten (Reihenfolge = Liste)."""
    sections: list[str] = []
    sources: list[list[str]] = []
    for n, path in enumerate(paths, start=1):
        caption = f"Diagramm {n}: {path.stem}"
        sections.append(
            SECTION.replace("__CAPTION__", caption).replace("__N__", str(n))
        )
        sources.append([f"d{n}", path.read_text(encoding="utf-8")])
    return TEMPLATE.replace("__SECTIONS__", "\n".join(sections)).replace(
        "__SOURCES__", json.dumps(sources)
    )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "mmd", nargs="+", type=Path, help=".mmd-Quelltexte (Reihenfolge)"
    )
    parser.add_argument(
        "--out",
        type=Path,
        default=Path("render.html"),
        help="Pfad der erzeugten HTML-Datei (Default: ./render.html)",
    )
    args = parser.parse_args(argv)

    for path in args.mmd:
        if not path.is_file():
            print(f"fehlt: {path}", file=sys.stderr)
            return 2

    out_dir = args.out.parent
    out_dir.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(ensure_mermaid(), out_dir / "mermaid.min.js")

    args.out.write_text(build_html(args.mmd), encoding="utf-8")
    print(f"{args.out} mit {len(args.mmd)} Diagramm(en) geschrieben")
    return 0


if __name__ == "__main__":
    sys.exit(main())
