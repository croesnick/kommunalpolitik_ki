#!/usr/bin/env python3
"""Tests für den SVG-Fidelity-Check: Round-Trip und gezielte Mutationen."""

import subprocess
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

from check_svg_fidelity import SVG_NS, XML_SPACE, check
from render_terminal_svg import main as render_main

NS_TEXT = f"{{{SVG_NS}}}text"
NS_TSPAN = f"{{{SVG_NS}}}tspan"
NS_RECT = f"{{{SVG_NS}}}rect"

SCRIPTS = Path(__file__).parent
RENDERER = SCRIPTS / "render_terminal_svg.py"
CHECKER = SCRIPTS / "check_svg_fidelity.py"

# Ein Capture mit allen Styles in einer Datei: bold, dim, 256-Color, bright,
# Default-FG, Reverse-Spaces als Cursor, Entities, harmlose Non-SGR-Escapes,
# ein 6er-Leerraum-Run (Renderer cropt auf 2) und 4 Zeilen Leerraum am Ende
# (werden gepoppt).
CAPTURE = "\n".join(
    [
        "Regelblock: \x1b[1mfett gedruckt\x1b[0m wieder normal",
        "\x1b[2mSchwacher Text\x1b[0m wieder normal",
        "\x1b[38;5;208mOrange aus der 256er-Palette\x1b[0m fertig",
        "\x1b[92mLeuchtend gruen\x1b[0m fertig",
        "Eingabe \x1b[7m   \x1b[0m danach",
        '<html> & "Anfuehrungszeichen"',
        "\x1b[KLoeschen? \x1b[?25hCursor wieder da",
        "",
        "",
        "",
        "",
        "",
        "",
        "Fusszeile nach dem Leerraum",
        "",
        "",
        "",
        "",
    ]
)
ENTITY_LINE = 5
EXPECTED_ROWS = 10
BLANK_ROWS = 2


def render_capture(tmp_path, monkeypatch, capture=CAPTURE, title="Fenstertitel"):
    src = tmp_path / "capture.txt"
    src.write_text(capture, encoding="utf-8")
    out = tmp_path / "out.svg"
    monkeypatch.setattr(
        sys, "argv", ["render_terminal_svg.py", str(src), str(out), title]
    )
    render_main()
    return src, out


def content_rows(root):
    return [el for el in root.iter(NS_TEXT) if el.get(XML_SPACE) == "preserve"]


def all_tspans(root):
    return [ts for row in content_rows(root) for ts in row.iter(NS_TSPAN)]


def parent_map(root):
    return {child: parent for parent in root.iter() for child in parent}


def mutate_svg(svg_path, fn):
    """Lade das SVG, wende fn auf das Root-Element an, schreibe es zurück."""
    ET.register_namespace("", SVG_NS)
    root = ET.parse(svg_path).getroot()
    fn(root)
    with open(svg_path, "w", encoding="utf-8") as f:
        ET.ElementTree(root).write(f, encoding="unicode")
    return root


def test_round_trip_fidelity_ok(tmp_path, monkeypatch):
    src, out = render_capture(tmp_path, monkeypatch)
    assert check(src, out) == (True, [])


def test_missing_tspan_fails(tmp_path, monkeypatch):
    src, out = render_capture(tmp_path, monkeypatch)

    def drop_one(root):
        row = content_rows(root)[0]
        row.remove(list(row.iter(NS_TSPAN))[0])

    mutate_svg(out, drop_one)
    ok, problems = check(src, out)
    assert ok is False
    assert "line 1: char count mismatch svg=38 capture=39" in problems


def test_wrong_color_fails(tmp_path, monkeypatch):
    src, out = render_capture(tmp_path, monkeypatch)

    def recolor(root):
        all_tspans(root)[0].set("fill", "#123456")

    mutate_svg(out, recolor)
    ok, problems = check(src, out)
    assert ok is False
    fill_problems = [p for p in problems if "fill differs" in p]
    assert len(fill_problems) == 1
    assert "expected=#" in fill_problems[0]
    assert "got=#123456" in fill_problems[0]


def test_missing_bold_fails(tmp_path, monkeypatch):
    src, out = render_capture(tmp_path, monkeypatch)

    def strip_bold(root):
        bold = [ts for ts in all_tspans(root) if ts.get("font-weight") == "bold"]
        del bold[0].attrib["font-weight"]

    mutate_svg(out, strip_bold)
    ok, problems = check(src, out)
    assert ok is False
    assert any("font-weight differs expected=bold got=none" in p for p in problems)


def test_missing_dim_fails(tmp_path, monkeypatch):
    src, out = render_capture(tmp_path, monkeypatch)

    def strip_dim(root):
        dim = [ts for ts in all_tspans(root) if ts.get("fill-opacity") == "0.62"]
        del dim[0].attrib["fill-opacity"]

    mutate_svg(out, strip_dim)
    ok, problems = check(src, out)
    assert ok is False
    assert any("fill-opacity differs expected=dim got=none" in p for p in problems)


def test_rect_count_fails(tmp_path, monkeypatch):
    src, out = render_capture(tmp_path, monkeypatch)

    def drop_one_rect(root):
        rects = [el for el in root.iter(NS_RECT) if el.get("rx") == "2"]
        parent_map(root)[rects[0]].remove(rects[0])

    mutate_svg(out, drop_one_rect)
    ok, problems = check(src, out)
    assert ok is False
    assert "RECT COUNT MISMATCH svg=2 capture=3" in problems


def test_line_count_fails(tmp_path, monkeypatch):
    src, out = render_capture(tmp_path, monkeypatch)

    def drop_one_row(root):
        row = content_rows(root)[0]
        parent_map(root)[row].remove(row)

    mutate_svg(out, drop_one_row)
    ok, problems = check(src, out)
    assert ok is False
    assert "LINE COUNT MISMATCH svg=9 capture=10" in problems


def test_blank_run_collapse(tmp_path, monkeypatch):
    src, out = render_capture(tmp_path, monkeypatch)
    root = ET.parse(out).getroot()
    blank = [row for row in content_rows(root) if list(row.iter(NS_TSPAN)) == []]
    assert len(blank) == BLANK_ROWS
    assert check(src, out) == (True, [])


def test_entities_round_trip(tmp_path, monkeypatch):
    src, out = render_capture(tmp_path, monkeypatch)
    root = ET.parse(out).getroot()
    row = content_rows(root)[ENTITY_LINE]
    text = "".join(ts.text or "" for ts in row.iter(NS_TSPAN))
    assert text == '<html> & "Anfuehrungszeichen"'
    assert check(src, out) == (True, [])


def test_title_not_a_content_row(tmp_path, monkeypatch):
    src, out = render_capture(tmp_path, monkeypatch, title="Fenstertitel X")
    root = ET.parse(out).getroot()
    assert len(content_rows(root)) == EXPECTED_ROWS
    assert check(src, out) == (True, [])


def test_cli_contract(tmp_path):
    src = tmp_path / "capture.txt"
    src.write_text(CAPTURE, encoding="utf-8")
    out = tmp_path / "out.svg"

    rendered = subprocess.run(
        [sys.executable, str(RENDERER), str(src), str(out), "Fenstertitel X"],
        capture_output=True,
        text=True,
        check=False,
    )
    assert rendered.returncode == 0
    assert rendered.stdout.startswith("lines=")

    checked = subprocess.run(
        [sys.executable, str(CHECKER), str(src), str(out)],
        capture_output=True,
        text=True,
        check=False,
    )
    assert checked.returncode == 0
    assert "FIDELITY OK" in checked.stdout

    def recolor(root):
        all_tspans(root)[0].set("fill", "#deadbe")

    mutate_svg(out, recolor)
    corrupted = subprocess.run(
        [sys.executable, str(CHECKER), str(src), str(out)],
        capture_output=True,
        text=True,
        check=False,
    )
    assert corrupted.returncode == 1
    assert "FIDELITY FAILED" in corrupted.stdout


def test_osc_links_are_dropped(tmp_path, monkeypatch):
    capture = "\n".join(
        [
            "Quelle: \x1b]8;;https://example.org\x07RIS\x1b]8;;\x07 fertig",
            "\x1b]8;;https://example.org\x1b\\Link\x1b]8;;\x1b\\ mit ST",
        ]
    )
    src, out = render_capture(tmp_path, monkeypatch, capture=capture)
    root = ET.parse(out).getroot()
    text = [
        "".join(ts.text or "" for ts in row.iter(NS_TSPAN))
        for row in content_rows(root)
    ]
    assert text[0].rstrip() == "Quelle: RIS fertig"
    assert text[1].rstrip() == "Link mit ST"
    assert check(src, out) == (True, [])
