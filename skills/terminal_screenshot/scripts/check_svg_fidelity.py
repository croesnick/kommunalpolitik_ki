#!/usr/bin/env python3
"""Check: SVG-Inhalt (Text, Farben, Cursor-Blöcke) == Capture,
strukturell per XML-Parser."""

import sys
import xml.etree.ElementTree as ET

from render_terminal_svg import collapse_blanks, color_for, parse_line

SVG_NS = "http://www.w3.org/2000/svg"
NS_TEXT = f"{{{SVG_NS}}}text"
NS_TSPAN = f"{{{SVG_NS}}}tspan"
NS_RECT = f"{{{SVG_NS}}}rect"
XML_SPACE = "{http://www.w3.org/XML/1998/namespace}space"


def _expected_side(capture_path):
    """Pro Capture-Zeile: Liste von (char, fill, bold, dim) + Anzahl Cursor-Blöcke.

    Die Erwartung wird aus den eigenen Parse-Funktionen des Renderers
    abgeleitet (gleiche Vorverarbeitung, gleiche Emissions-Schleife) — keine
    duplizierte Strip-/Collapse-Logik, die vom Renderer abdriften kann.
    """
    with open(capture_path, encoding="utf-8") as f:
        raw_lines = f.read().split("\n")
    lines = collapse_blanks(raw_lines)

    expected = []
    for raw in lines:
        chars = []
        rects = 0
        for text, style in parse_line(raw):
            fill = color_for(style)
            for ch in text:
                if style["rev"] and ch == " ":
                    rects += 1
                else:
                    chars.append((ch, fill, style["bold"], style["dim"]))
        expected.append((chars, rects))
    return expected


def _actual_side(svg_path):
    """Pro Inhaltszeile: Liste von (char, fill, bold, dim) + Cursor-Block-Zahl.

    Inhaltszeilen sind die <text>-Elemente mit xml:space="preserve" (der
    Fenstertitel hat das Attribut nicht); ein Tspan pro Zeichen, in
    Dokumentenreihenfolge. Cursor-Blöcke sind die Rects mit rx="2".
    """
    root = ET.parse(svg_path).getroot()
    rows = [el for el in root.iter(NS_TEXT) if el.get(XML_SPACE) == "preserve"]

    actual = []
    for row in rows:
        chars = []
        for tspan in row.iter(NS_TSPAN):
            char = (
                tspan.text or "",
                tspan.get("fill"),
                tspan.get("font-weight") == "bold",
                tspan.get("fill-opacity") == "0.62",
            )
            chars.append(char)
        actual.append(chars)
    rects = sum(1 for el in root.iter(NS_RECT) if el.get("rx") == "2")
    return actual, rects


def check(capture_path, svg_path):
    """Vergleiche Capture-Ableitung und geparstes SVG; gib (ok, Probleme) zurück."""
    expected = _expected_side(capture_path)
    actual, svg_rects = _actual_side(svg_path)
    problems = []
    ok = True

    exp_rects = sum(n for _, n in expected)
    if svg_rects != exp_rects:
        ok = False
        problems.append(f"RECT COUNT MISMATCH svg={svg_rects} capture={exp_rects}")

    if len(actual) != len(expected):
        ok = False
        problems.append(
            f"LINE COUNT MISMATCH svg={len(actual)} capture={len(expected)}"
        )

    # strict=False: Längenunterschiede werden oben gemeldet; hier zählt der
    # zeilenweise Diff, solange beide Seiten Zeilen haben.
    for i, (exp_line, act_line) in enumerate(zip(expected, actual, strict=False)):
        exp_chars, _ = exp_line
        n = i + 1
        if len(act_line) != len(exp_chars):
            ok = False
            problems.append(
                f"line {n}: char count mismatch svg={len(act_line)} "
                f"capture={len(exp_chars)}"
            )
        for m, (exp, act) in enumerate(zip(exp_chars, act_line, strict=False)):
            e_char, e_fill, e_bold, e_dim = exp
            a_char, a_fill, a_bold, a_dim = act
            cm = m + 1
            if a_char != e_char:
                ok = False
                problems.append(
                    f"line {n} char {cm}: text differs "
                    f"svg={a_char!r} capture={e_char!r}"
                )
            if a_fill != e_fill:
                ok = False
                problems.append(
                    f"line {n} char {cm}: fill differs expected={e_fill} got={a_fill}"
                )
            e_weight = "bold" if e_bold else "none"
            a_weight = "bold" if a_bold else "none"
            if a_weight != e_weight:
                ok = False
                problems.append(
                    f"line {n} char {cm}: font-weight differs "
                    f"expected={e_weight} got={a_weight}"
                )
            e_op = "dim" if e_dim else "none"
            a_op = "dim" if a_dim else "none"
            if a_op != e_op:
                ok = False
                problems.append(
                    f"line {n} char {cm}: fill-opacity differs "
                    f"expected={e_op} got={a_op}"
                )
    return ok, problems


def main() -> None:
    src, svg = sys.argv[1], sys.argv[2]
    ok, problems = check(src, svg)
    for problem in problems:
        print(problem)
    print("FIDELITY OK" if ok else "FIDELITY FAILED")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
