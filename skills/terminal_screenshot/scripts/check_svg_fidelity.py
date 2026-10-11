#!/usr/bin/env python3
"""Check: SVG text content == cleaned capture text."""
import re
import sys

ANSI_RE = re.compile(r"\x1b\[([0-9;?]*)([a-zA-Z])")
# reversed-space runs (terminal cursor) are drawn as rects in the SVG, not text
REV_SPACE_RE = re.compile(r"\x1b\[[0-9;]*7m +\x1b\[[0-9;]*m")

src, svg = sys.argv[1], sys.argv[2]

with open(src, encoding="utf-8") as f:
    raw_lines = f.read().split("\n")


def plain(ln):
    return ANSI_RE.sub("", REV_SPACE_RE.sub("", ln)).rstrip("\n").rstrip("\r")


# same collapse logic as renderer
out, run = [], 0
for ln in raw_lines:
    if plain(ln).strip() == "":
        run += 1
        if run <= 2:
            out.append(plain(ln))
    else:
        run = 0
        out.append(plain(ln))
while out and out[-1].strip() == "":
    out.pop()

with open(svg, encoding="utf-8") as f:
    svg_text = f.read()

text_blocks = re.findall(r'<text [^>]*xml:space="preserve">(.*?)</text>', svg_text, re.S)
svg_lines = []
for block in text_blocks:
    svg_lines.append("".join(re.findall(r"<tspan[^>]*>(.*?)</tspan>", block, re.S)))

import html  # noqa: E402

ok = True
if len(svg_lines) != len(out):
    ok = False
    print(f"LINE COUNT MISMATCH svg={len(svg_lines)} capture={len(out)}")
for i, (a, b) in enumerate(zip(svg_lines, out)):
    if html.unescape(a) != b:
        ok = False
        print(f"DIFF line {i+1}:\n  svg    : {a!r}\n  capture: {b!r}")

print("FIDELITY OK" if ok else "FIDELITY FAILED")
sys.exit(0 if ok else 1)
