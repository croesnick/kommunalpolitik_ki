#!/usr/bin/env python3
"""YAML-Frontmatter von Vault-Notizen prüfen (Single-Quote-Regel, #53).

Dies ist die eine Stelle, an der die Single-Quote-Regel steht, die für
alle Skills mit strukturiertem Vault-Write gilt (sitzungsvorbereitung,
bericht_aus_dem_stadtrat; später Foerderrecherche-Persistenz #36 und
Buergeranliegen #38):

- YAML-Werte mit externem Text (AZ-Titel, RIS-Titel, Notiz-Titel)
  immer in Single-Quotes setzen. Innerhalb von Single-Quotes sind
  Double-Quotes, deutsche Anführungszeichen und Sonderzeichen sicher;
  ein `'` im Wert wird durch Verdopplung escaped: `'It''s a test'`.

      titel: '„Völlig konsterniert" – Anwohner zwischen Verzweiflung'

- Einfache Werte ohne Sonderzeichen brauchen keine Quotes:
  `gremium: Stadtrat`, `ort: Buchloe`, `url: https://…`.
- Nie Double-Quotes als Wrapper für externen Text: ein `"` im Wert
  schließt den String vorzeitig, der Rest der Zeile ist unparserbar.
  Ausnahme: ein Wert mit `'`, aber ohne `"` im Wert, darf in
  Double-Quotes stehen: `anlass: "It's a test"`.
- Ein ` #` im Wert leitet einen YAML-Kommentar ein und schneidet den
  Wert ab; ein `: ` im Wert trennt key und Wert. Beides gehört in
  Single-Quotes.
- Ein Single-Quote-Wert darf über mehrere Zeilen laufen (Fortsetzungs-
  zeilen eingerückt); er endet am schließenden `'`.

Geprüft wird diese Konvention, nicht allgemeine YAML-Syntax: Flow-Style
(`[a, b]`, `{k: v}`), Block-Indikatoren (`|`, `>`), Anchoren und plain
skalare Fortsetzungszeilen sind nicht Teil der Konvention und werden als
Fehler gemeldet.

Aufruf:

    python3 check_frontmatter.py <notiz.md> [weitere.md …]
    python3 check_frontmatter.py -        # Notiz von stdin, z. B.:
    obsidian vault="…" read file="…" | python3 check_frontmatter.py -

Ausgabe: pro Notiz entweder `OK <name>: Frontmatter valide` oder je
Fehler eine Zeile `FEHLER <name>:<zeile>: <grund>`.
Exit 0 = alles valide, 1 = mindestens ein Fehler, 2 = Aufruf/IO-Fehler.
"""

import re
import sys

# key: Wert, optional als Listeneintrag ("- key: Wert") und eingerückt
KEY_VALUE = re.compile(r"^(\s*)(?:- )?([A-Za-z0-9_][\w.-]*): ?(.*)$")
# Listeneintrag ohne key ("- Wert")
LIST_ITEM = re.compile(r"^(\s*)- (.*)$")

# Anführungszeichen, die einen plain Wert regelwidrig machen: ASCII plus
# die im deutschen Sprachraum üblichen typografischen Varianten.
ANFUEHRUNGSZEICHEN = "\"'„“”‚‘’«»‹›"
# YAML-Indikatoren, mit denen ein plain Wert nicht beginnen darf.
PLAIN_INDIKATOREN = "!&*[]{},#|>%@`"


def _scan_single_quoted(text):
    """Text innerhalb eines Single-Quote-Werts scannen.

    `''` ist das escaped `'`. Rückgabe (geschlossen, rest): geschlossen
    True mit dem Text nach dem schließenden `'`, sonst False, "".
    """
    i = 0
    while i < len(text):
        if text[i] == "'":
            if i + 1 < len(text) and text[i + 1] == "'":
                i += 2
                continue
            return True, text[i + 1 :]
        i += 1
    return False, ""


def _scan_double_quoted(text):
    """Text innerhalb eines Double-Quote-Werts scannen; `\\"` ist escaped.

    Rückgabe wie bei _scan_single_quoted.
    """
    i = 0
    while i < len(text):
        if text[i] == "\\":
            i += 2
            continue
        if text[i] == '"':
            return True, text[i + 1 :]
        i += 1
    return False, ""


def _rest_ok(rest):
    """True, wenn nach einem geschlossenen Wert nur noch Kommentar steht."""
    return rest == "" or (rest[0].isspace() and rest.lstrip().startswith("#"))


def _check_scalar(value, line_no):
    """Einen Wert gegen die Single-Quote-Regel prüfen.

    Rückgabe (fehler, offen): fehler ist eine Liste (zeile, grund),
    offen True, wenn ein Single-Quote-Wert über diese Zeile hinausläuft.
    """
    fehler = []
    stripped = value.strip()
    if not stripped:
        return fehler, False

    if stripped.startswith("'"):
        geschlossen, rest = _scan_single_quoted(stripped[1:])
        if geschlossen and not _rest_ok(rest):
            fehler.append(
                (line_no, f"nach dem schließenden ' steht Inhalt: {rest.strip()!r}")
            )
        return fehler, not geschlossen

    if stripped.startswith('"'):
        geschlossen, rest = _scan_double_quoted(stripped[1:])
        if not geschlossen:
            fehler.append((line_no, "Double-Quote nicht geschlossen"))
        elif not _rest_ok(rest):
            fehler.append(
                (
                    line_no,
                    'Wert endet vorzeitig: ein " im Wert schließt den String — '
                    "Single-Quotes verwenden",
                )
            )
        return fehler, False

    # plain: sieht aus wie ein sicherer Wert, wenn keine Regel greift
    if stripped.startswith("#"):
        fehler.append((line_no, "Wert beginnt mit '#' — der Wert wäre ein Kommentar"))
    elif stripped[0] in PLAIN_INDIKATOREN:
        fehler.append(
            (
                line_no,
                f"plain Wert beginnt mit {stripped[0]!r} — Single-Quotes verwenden",
            )
        )
    if ": " in stripped:
        fehler.append(
            (line_no, "': ' im Wert trennt key und Wert — Single-Quotes verwenden")
        )
    if " #" in stripped:
        fehler.append(
            (line_no, "' #' leitet einen Kommentar ein — Wert wird abgeschnitten")
        )
    for zeichen in stripped:
        if zeichen in ANFUEHRUNGSZEICHEN:
            fehler.append(
                (
                    line_no,
                    f"Anführungszeichen {zeichen!r} im plain Wert — "
                    "Single-Quotes verwenden",
                )
            )
            break
    return fehler, False


def _check_block(block):
    """Frontmatter-Zeilen (ohne die '---' der Begrenzung) prüfen."""
    fehler = []
    offen_in = None  # 0-basierte Zeile, in der ein Single-Quote-Wert beginnt
    for idx, line in enumerate(block):
        line_no = idx + 2  # Frontmatter beginnt in Dateizeile 2
        if offen_in is not None:
            geschlossen, rest = _scan_single_quoted(line)
            if geschlossen:
                if not _rest_ok(rest):
                    fehler.append(
                        (
                            line_no,
                            f"nach dem schließenden ' steht Inhalt: {rest.strip()!r}",
                        )
                    )
                offen_in = None
            continue
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        match = KEY_VALUE.match(line)
        if match:
            wert_fehler, offen = _check_scalar(match.group(3), line_no)
            fehler.extend(wert_fehler)
            if offen:
                offen_in = idx
            continue
        match = LIST_ITEM.match(line)
        if match:
            wert_fehler, offen = _check_scalar(match.group(2), line_no)
            fehler.extend(wert_fehler)
            if offen:
                offen_in = idx
            continue
        fehler.append(
            (
                line_no,
                "passt nicht zur Konvention: 'key: Wert', '- key: Wert', "
                "'- Wert', Kommentar oder Single-Quote-Fortsetzung erwartet",
            )
        )
    if offen_in is not None:
        fehler.append((offen_in + 2, "Single-Quote nicht geschlossen"))
    return fehler


def check_frontmatter(text):
    """Frontmatter einer Notiz prüfen; Rückgabe Liste (zeile, grund)."""
    lines = text.split("\n")
    if not lines or lines[0].rstrip() != "---":
        return [(1, "kein Frontmatter: erste Zeile muss '---' sein")]
    ende = None
    for idx in range(1, len(lines)):
        if lines[idx].rstrip() == "---":
            ende = idx
            break
    if ende is None:
        return [(1, "Frontmatter nicht geschlossen: schließendes '---' fehlt")]
    block = lines[1:ende]
    if not any(line.strip() for line in block):
        return [(2, "Frontmatter ist leer")]
    return _check_block(block)


def main(argv):
    """Pfad-Argumente oder '-' für stdin; siehe Moduldocstring."""
    if not argv:
        print("Aufruf: check_frontmatter.py <notiz.md> [-]", file=sys.stderr)
        return 2
    fehler_gesamt = []
    for pfad in argv:
        if pfad == "-":
            text = sys.stdin.read()
            name = "<stdin>"
        else:
            try:
                with open(pfad, encoding="utf-8") as datei:
                    text = datei.read()
            except OSError as e:
                print(f"FEHLER {pfad}: {e}", file=sys.stderr)
                return 2
            name = pfad
        fehler = check_frontmatter(text)
        if fehler:
            for zeile, grund in fehler:
                print(f"FEHLER {name}:{zeile}: {grund}")
            fehler_gesamt.extend(fehler)
        else:
            print(f"OK {name}: Frontmatter valide")
    return 1 if fehler_gesamt else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
