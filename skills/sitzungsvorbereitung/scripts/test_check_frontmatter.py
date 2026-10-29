#!/usr/bin/env python3
"""Tests für check_frontmatter: die Bug-Klasse aus WF 1 („…", :, #,
mehrzeilige Titel) plus Struktur- und Konventionsfehler."""

import subprocess
import sys
from pathlib import Path

from check_frontmatter import check_frontmatter

SCRIPT = Path(__file__).parent / "check_frontmatter.py"

# Das Frontmatter der Sitzungsmappe-Vorlage: verschachtelte quellen-Liste,
# Single-Quotes mit externem Text, plain Werte (Datum, URL), Kommentar
# hinter einem geschlossenen Wert.
GUELTIGE_MAPPE = """---
type: sitzungsmappe
sitzung_id: 2025-07-24-001
sitzung_datum: 2025-07-24
gremium: Stadtrat
ort: Buchloe
ris_url: https://ris.komuna.net/vgbuchloe/Meeting.mvc/Calendar?atDate=1.1.2025
titel: '„Völlig konsterniert" – Anwohner zwischen Verzweiflung'
quellen:
  - typ: sitzung
    titel: 'RIS-Sitzung 2025-07-24-001 vom 2025-07-24'
    abrufdatum: 2025-07-15
  - typ: presse
    titel: 'AZ: Antrag "für den Rat"'  # Single-Quotes! Siehe Quoting-Regel
    url: https://www.allgaeuer-zeitung.de/artikel/123
    abrufdatum: 2025-07-15
tags:
  - Stadtrat
  - Buchloe
---

# Sitzungsmappe

Body, egal was hier steht.
"""

# Der historische AZ-Fall: double-quoted Wrapper, im Wert ein ASCII-"
# schließt den String vorzeitig — der Rest der Zeile ist unparserbar.
AZ_TITEL_KAPUTT = """---
titel: "„Völlig konsterniert" – Anwohner zwischen Verzweiflung"
---

Body.
"""


def gründe(text):
    """Nur die Fehlertexte, ohne Zeilennummern."""
    return [grund for _, grund in check_frontmatter(text)]


def zeilen(text):
    """Nur die Zeilennummern der Fehler."""
    return [zeile for zeile, _ in check_frontmatter(text)]


def test_gueltige_mappe_ist_ok():
    assert check_frontmatter(GUELTIGE_MAPPE) == []


def test_az_titel_in_single_quotes_ist_ok():
    text = "---\ntitel: '„Völlig konsterniert\" – Anwohner'\n---\n"
    assert check_frontmatter(text) == []


def test_az_titel_in_double_quotes_endet_vorzeitig():
    # Zeile 2 trägt den kaputten Wert; die Meldung nennt den Grund.
    assert zeilen(AZ_TITEL_KAPUTT) == [2]
    assert any("vorzeitig" in g for g in gründe(AZ_TITEL_KAPUTT))


def test_apostrophe_nach_ausnahme():
    # 'It''s a test' (escaped) und "It's a test" (Ausnahme) sind ok,
    # ein " im Double-Quote-Wert endet vorzeitig.
    ok_escaped = "---\ntitel: 'It''s a test'\n---\n"
    ok_ausnahme = '---\nanlass: "It\'s a test"\n---\n'
    assert check_frontmatter(ok_escaped) == []
    assert check_frontmatter(ok_ausnahme) == []
    kaputt = '---\ntitel: "Say "cheese" now"\n---\n'
    assert any("vorzeitig" in g for g in gründe(kaputt))


def test_doppelpunkt_im_wert():
    # plain: ": " trennt key und Wert; single-quoted ist sicher.
    kaputt = "---\ntitel: TOP 3: Marktplatz\nanlass: Stammtisch: Fragenrunde\n---\n"
    assert zeilen(kaputt) == [2, 3]
    ok = "---\ntitel: 'TOP 3: Marktplatz'\n---\n"
    assert check_frontmatter(ok) == []
    # Doppelpunkt ohne Folgestelle ist plain erlaubt (https://…).
    url = "---\nris_url: https://ris.komuna.net/vgbuchloe\n---\n"
    assert check_frontmatter(url) == []


def test_hash_im_wert():
    # plain: " #" leitet einen Kommentar ein, der Wert wird abgeschnitten;
    # "#1" am Anfang wäre gleich ganz ein Kommentar. Single-Quotes sind ok.
    kaputt = "---\ntitel: Bericht #3 vom Rat\ntags: #Stadtrat\n---\n"
    assert zeilen(kaputt) == [2, 3]
    assert any("abgeschnitten" in g for g in gründe(kaputt))
    assert any("Kommentar" in g for g in gründe(kaputt))
    ok = "---\ntitel: 'Bericht #3 vom Rat'\n---\n"
    assert check_frontmatter(ok) == []


def test_mehrzeiliger_titel_in_single_quotes():
    # Single-Quote-Werte dürfen über Zeilen laufen (eingerückt).
    text = "---\ntitel: 'Erste Zeile des Titels\n  zweite Zeile des Titels'\n---\n"
    assert check_frontmatter(text) == []


def test_mehrzeiliger_titel_nicht_geschlossen():
    # Die Meldung nennt die Zeile, in der der Wert beginnt (Zeile 2).
    text = "---\ntitel: 'offen und nie geschlossen\n  und weiter\n---\n"
    assert zeilen(text) == [2]
    assert any("nicht geschlossen" in g for g in gründe(text))


def test_strukturfehler():
    kein = "Kein Frontmatter hier.\n"
    assert zeilen(kein) == [1]
    offen = "---\ntitel: x\nBody ohne schließendes '---'\n"
    assert any("nicht geschlossen" in g for g in gründe(offen))
    leer = "---\n---\nBody.\n"
    assert any("leer" in g for g in gründe(leer))
    # Zeilen ohne key, Liste oder Kommentar.
    unruly = "---\ntitel: x\neine freie Zeile\n---\n"
    assert any("Konvention" in g for g in gründe(unruly))


def test_kommentare_und_leerzeilen_im_block_sind_ok():
    text = "---\n# Kommentar\n\ntitel: 'x'\n\n---\nBody.\n"
    assert check_frontmatter(text) == []


def test_cli_datei_und_stdin(tmp_path):
    # Exit 0 + OK auf Datei, Exit 1 + FEHLER mit Zeile auf stdin.
    datei = tmp_path / "mappe.md"
    datei.write_text(GUELTIGE_MAPPE, encoding="utf-8")
    lauf = subprocess.run(
        [sys.executable, str(SCRIPT), str(datei)],
        capture_output=True,
        text=True,
        check=False,
    )
    assert lauf.returncode == 0
    assert "OK" in lauf.stdout

    lauf = subprocess.run(
        [sys.executable, str(SCRIPT), "-"],
        input=AZ_TITEL_KAPUTT,
        capture_output=True,
        text=True,
        check=False,
    )
    assert lauf.returncode == 1
    assert "FEHLER <stdin>:2:" in lauf.stdout


def test_cli_aufruffehler():
    lauf = subprocess.run(
        [sys.executable, str(SCRIPT)],
        capture_output=True,
        text=True,
        check=False,
    )
    assert lauf.returncode == 2
    assert "Aufruf" in lauf.stderr
