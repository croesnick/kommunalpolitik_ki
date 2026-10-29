#!/usr/bin/env python3
"""Render a tmux capture-pane (with ANSI SGR) into a terminal-style SVG.

Usage: render_terminal_svg.py <capture.txt> <out.svg> <title> [hell]
Blank-line runs > 4 are collapsed to 2 (crops empty screen area, keeps content).
"hell" draws a light terminal (for captures of a light pi theme).
"""

import html
import re
import sys

CHAR_W = 8.1  # Menlo advance at 13.5px
FONT_SIZE = 13.5
LINE_H = 20
PAD_X = 26
CHROME_H = 34
COLS = 112

BASE_FG = "#c9d1d9"
BG = "#0d1117"
TITLE_FG = "#6e7681"
DIM_DEFAULT = "#6e7681"
BOLD_FG = "#ffffff"
RULE = "#21262d"

# Light terminal: default colors for text without an explicit SGR color.
LIGHT = {
    "BASE_FG": "#1f2328",
    "BG": "#ffffff",
    "TITLE_FG": "#6e7781",
    "DIM_DEFAULT": "#6e7781",
    "BOLD_FG": "#1f2328",
    "RULE": "#d0d7de",
}


def set_theme(name):
    """Switch the default colors; renderer and fidelity check share them."""
    if name == "hell":
        globals().update(LIGHT)
    elif name is not None:
        raise SystemExit(f"unknown theme: {name}")


XTERM = [
    "#000000",
    "#cd3131",
    "#0dbc79",
    "#e5e510",
    "#2472c8",
    "#d670d6",
    "#29b8db",
    "#e5e5e5",
]
BRIGHT = [
    "#666666",
    "#f14c4c",
    "#23d18b",
    "#f5f543",
    "#3b8eea",
    "#d670d6",
    "#29b8db",
    "#ffffff",
]

RESET_STYLE = {"fg": None, "bg": None, "bold": False, "dim": False, "rev": False}


def build_256_palette():
    pal = list(XTERM) + list(BRIGHT)
    steps = [0, 95, 135, 175, 215, 255]
    for r in steps:
        for g in steps:
            for b in steps:
                pal.append(f"#{r:02x}{g:02x}{b:02x}")
    for i in range(24):
        v = 8 + i * 10
        pal.append(f"#{v:02x}{v:02x}{v:02x}")
    return pal


PAL256 = build_256_palette()
# CSI-Sequenzen (SGR wird ausgewertet, der Rest verworfen) und OSC-Sequenzen
# wie OSC-8-Links, beendet mit BEL oder ESC \. Ohne die OSC-Alternative
# landeten BEL und Link-Ziel im SVG, und das XML war ungueltig.
ANSI_RE = re.compile(r"\x1b\[([0-9;?]*)([a-zA-Z])|\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)")


def parse_line(raw):
    """Return list of (text, style) segments for one line."""
    segs = []
    style = dict(RESET_STYLE)
    pos = 0
    text_buf = []

    def flush():
        if text_buf:
            segs.append(("".join(text_buf), dict(style)))
            del text_buf[:]

    for m in ANSI_RE.finditer(raw):
        text_buf.append(raw[pos : m.start()])
        pos = m.end()
        if m.group(2) != "m":
            continue  # strip non-SGR escapes
        flush()
        params = m.group(1)
        codes = [int(c) if c else 0 for c in params.split(";")] if params else [0]
        i = 0
        while i < len(codes):
            c = codes[i]
            if c == 0:
                style = dict(RESET_STYLE)
            elif c == 1:
                style["bold"] = True
            elif c == 2:
                style["dim"] = True
            elif c == 22:
                style["bold"] = False
                style["dim"] = False
            elif c == 7:
                style["rev"] = True
            elif c == 27:
                style["rev"] = False
            elif 30 <= c <= 37:
                style["fg"] = XTERM[c - 30]
            elif 90 <= c <= 97:
                style["fg"] = BRIGHT[c - 90]
            elif c == 39:
                style["fg"] = None
            elif 40 <= c <= 47 or 90 <= c <= 97 or c == 49:
                pass  # background: unused in this capture, keep default
            elif c == 38 and i + 1 < len(codes) and codes[i + 1] == 5:
                if i + 2 < len(codes):
                    style["fg"] = PAL256[codes[i + 2]]
                i += 2
            elif c == 38 and i + 1 < len(codes) and codes[i + 1] == 2:
                # Truecolor (pi-Themes): 38;2;r;g;b
                if i + 4 < len(codes):
                    r, g, b = codes[i + 2 : i + 5]
                    style["fg"] = f"#{r:02x}{g:02x}{b:02x}"
                i += 4
            elif c == 48 and i + 1 < len(codes):
                # Hintergrund wird nicht gezeichnet; die Farbwerte nicht als
                # eigene Codes lesen (sonst wird etwa ein "2" zu dim).
                i += {5: 2, 2: 4}.get(codes[i + 1], 0)
            i += 1
    text_buf.append(raw[pos:])
    flush()
    if not segs:
        segs = [("", dict(style))]
    return segs


def plain(raw):
    return ANSI_RE.sub("", raw).rstrip("\n").rstrip("\r")


def collapse_blanks(lines):
    out = []
    run = 0
    for ln in lines:
        if plain(ln).strip() == "":
            run += 1
            if run <= 2:
                out.append(ln)
        else:
            run = 0
            out.append(ln)
    while out and plain(out[-1]).strip() == "":
        out.pop()
    return out


def color_for(style):
    fg = style["fg"]
    if fg is None:
        fg = BOLD_FG if style["bold"] else (DIM_DEFAULT if style["dim"] else BASE_FG)
    return fg


def esc(s):
    return html.escape(s, quote=True)


def main():
    src, dst, title = sys.argv[1], sys.argv[2], sys.argv[3]
    set_theme(sys.argv[4] if len(sys.argv) > 4 else None)
    with open(src, encoding="utf-8") as f:
        raw_lines = f.read().split("\n")
    lines = collapse_blanks(raw_lines)
    n = len(lines)
    # tolerate renderers that ignore per-char x and flow at a wider advance
    safe_advance = 9.2
    width = COLS * safe_advance + 2 * PAD_X
    height = CHROME_H + 14 + n * LINE_H + 14

    parts = []
    parts.append(
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width:.0f}" '
        f'height="{height:.0f}" viewBox="0 0 {width:.0f} {height:.0f}" '
        "font-family=\"Menlo, Monaco, 'Courier New', monospace\">"
    )
    parts.append(f'<rect width="{width:.0f}" height="{height:.0f}" fill="{BG}"/>')
    # window chrome
    parts.append(
        f'<rect width="{width:.0f}" height="{height:.0f}" rx="10" fill="{BG}"/>'
    )
    parts.append(
        f'<line x1="0" y1="{CHROME_H}" x2="{width:.0f}" '
        f'y2="{CHROME_H}" stroke="{RULE}" stroke-width="1"/>'
    )
    for i, c in enumerate(["#ff5f57", "#febc2e", "#28c840"]):
        parts.append(f'<circle cx="{18 + i * 22}" cy="17" r="6" fill="{c}"/>')
    parts.append(
        f'<text x="{width / 2:.0f}" y="21.5" fill="{TITLE_FG}" font-size="12" '
        f'text-anchor="middle">{esc(title)}</text>'
    )
    # content — one tspan per character with absolute x so the layout
    # is independent of the viewer's font metrics
    body_x = PAD_X
    for idx, raw in enumerate(lines):
        y = CHROME_H + 14 + idx * LINE_H + FONT_SIZE
        parts.append(f'<text y="{y:.1f}" xml:space="preserve">')
        col = 0
        for text, style in parse_line(raw):
            fill = color_for(style)
            bold = ' font-weight="bold"' if style["bold"] else ""
            dim = ' fill-opacity="0.62"' if style["dim"] else ""
            for ch in text:
                if not (style["rev"] and ch == " "):
                    x = body_x + col * CHAR_W
                    parts.append(
                        f'<tspan x="{x:.1f}" fill="{fill}"{bold}{dim}>{esc(ch)}</tspan>'
                    )
                col += 1
        parts.append("</text>")
    # reversed-space cursor blocks (drawn after text so they sit on top)
    for idx, raw in enumerate(lines):
        y = CHROME_H + 14 + idx * LINE_H
        cursor_x = body_x
        for text, style in parse_line(raw):
            if style["rev"] and text.strip() == "":
                for k, ch in enumerate(text):
                    if ch == " ":
                        parts.append(
                            f'<rect x="{cursor_x + k * CHAR_W:.1f}" y="{y + 4}" '
                            f'width="{CHAR_W:.1f}" height="15" rx="2" '
                            f'fill="{BASE_FG}"/>'
                        )
            cursor_x += len(text) * CHAR_W
    parts.append("</svg>")
    with open(dst, "w", encoding="utf-8") as f:
        f.write("\n".join(parts))
    print(f"lines={n} width={width:.0f} height={height:.0f} -> {dst}")


if __name__ == "__main__":
    main()
