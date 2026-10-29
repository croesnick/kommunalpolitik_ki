"""Echter Lauf über den Server-Prozess: create_note mit einer Notiz voller
Sonderzeichen in einem Unterordner, der noch nicht existiert (#43, #52).

Der Test startet den echten MCP-Server über stdio (``python -m obsidian_mcp``)
und spricht ihn mit JSON-RPC an — derselbe Weg, den der AI-Harness über
``opencode.json`` geht. Gegenprüfungen: Die Datei liegt byte-exakt 1:1 im
Test-Vault (kein Shell-Quoting, keine Escapes), der Unterordner wurde selbst
angelegt, und ``read_note`` liefert denselben Inhalt zurück.
"""

import json
import os
import selectors
import subprocess
import sys
import time
from pathlib import Path

# Pfad in einem Unterordner, der im Test-Vault noch nicht existiert (#43):
# Umlaute, Leerzeichen, Bindestriche — so wie die Skills ihn bauen.
ZIEL_PFAD = "1 - Projects/Stadtrat Buchloe/Sitzungsmappen/2026-10-29 Sonderzeichen.md"

# Eine Notiz voller Sonderzeichen (#52): Frontmatter, Markdown-Tabelle,
# typografische und verschachtelte Anführungszeichen, Pfeile, Gedankenstriche,
# eckige Klammern — alles, was über die Shell regelmäßig brach.
INHALT = """---
type: sitzungsmappe
titel: '„Völlig konsterniert" – Anwohner: „alles [kaputt]"'
quellen:
  - typ: presse
    titel: 'AZ: Antrag "für den Rat"'
---

# Mappe mit Sonderzeichen

| Spalte | Wert |
|---|---|
| Titel | „Völlig konsterniert" |
| Pfeil | → dort |
| Zitat | „geschachtelt `"tief"`" |

- [Datum] und — Gedankenstrich
- It''s ein Apostroph
"""


class Server:
    """Der echte MCP-Server als Subprocess; Antworten nach id einsammeln."""

    def __init__(self, vault: Path) -> None:
        umgebung = {**os.environ, "OBSIDIAN_VAULT_PATH": str(vault)}
        self.prozess = subprocess.Popen(
            [sys.executable, "-m", "obsidian_mcp"],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            encoding="utf-8",
            env=umgebung,
        )
        self.selector = selectors.DefaultSelector()
        self.selector.register(self.prozess.stdout, selectors.EVENT_READ)

    def senden(self, nachricht: dict) -> None:
        assert self.prozess.stdin is not None
        self.prozess.stdin.write(json.dumps(nachricht) + "\n")
        self.prozess.stdin.flush()

    def antwort(self, msg_id: int, timeout: float = 30) -> dict:
        """Die nächste Antwort mit der passenden id; Notifications überspringen."""
        schluss = time.monotonic() + timeout
        while time.monotonic() < schluss:
            rest = schluss - time.monotonic()
            if not self.selector.select(rest):
                break
            zeile = self.prozess.stdout.readline()
            if not zeile:
                break
            nachricht = json.loads(zeile)
            if nachricht.get("id") == msg_id:
                return nachricht
        raise TimeoutError(f"Keine Antwort mit id {msg_id} vom Server.")

    def beenden(self) -> None:
        self.prozess.terminate()
        try:
            self.prozess.wait(timeout=5)
        except subprocess.TimeoutExpired:
            self.prozess.kill()


def test_create_note_mit_sonderzeichen_in_neuem_ordner(tmp_path):
    vault = tmp_path / "Test-Vault"
    vault.mkdir()
    # Der Zielordner darf noch nicht existieren — create_note legt ihn an.
    assert not (vault / "1 - Projects").exists()

    server = Server(vault)
    try:
        server.senden(
            {
                "jsonrpc": "2.0",
                "id": 1,
                "method": "initialize",
                "params": {
                    "protocolVersion": "2025-06-18",
                    "capabilities": {},
                    "clientInfo": {"name": "pytest", "version": "0"},
                },
            }
        )
        init = server.antwort(1)
        assert "result" in init, init
        server.senden({"jsonrpc": "2.0", "method": "notifications/initialized"})

        server.senden(
            {
                "jsonrpc": "2.0",
                "id": 2,
                "method": "tools/call",
                "params": {
                    "name": "create_note",
                    "arguments": {"path": ZIEL_PFAD, "content": INHALT},
                },
            }
        )
        ergebnis = server.antwort(2)
        assert "result" in ergebnis, ergebnis
        text = ergebnis["result"]["content"][0]["text"]
        assert "Notiz geschrieben" in text

        datei = vault / ZIEL_PFAD
        assert datei.is_file()
        assert datei.read_text(encoding="utf-8") == INHALT

        server.senden(
            {
                "jsonrpc": "2.0",
                "id": 3,
                "method": "tools/call",
                "params": {"name": "read_note", "arguments": {"path": ZIEL_PFAD}},
            }
        )
        gelesen = server.antwort(3)
        assert "result" in gelesen, gelesen
        assert gelesen["result"]["content"][0]["text"] == INHALT
    finally:
        server.beenden()
