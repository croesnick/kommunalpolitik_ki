"""MCP server, der die ratsinfo-CLI als Tools bereitstellt.

Wrapper um das Elixir-Escript `ratsinfo` (Ratsinformationssystem Buchloe).
Jedes Tool ruft den entsprechende CLI-Befehl als Subprocess auf und gibt
dessen stdout zurück. Bei Fehlern wird stderr als Fehlermeldung geliefert.
"""

from __future__ import annotations

import os
import subprocess

from mcp.server.fastmcp import FastMCP

mcp = FastMCP(
    "ratsinfo",
    instructions=(
        "MCP-Server für das Ratsinformationssystem Buchloe. "
        "Wrappt die ratsinfo-CLI (Elixir-Escript). "
        "Tools: search, show, sessions, sync, stats. "
        "Der Pfad zum Binary kann über die Umgebungsvariable "
        "RATSINFO_BINARY gesetzt werden (Default: 'ratsinfo')."
    ),
)

# Default-Timeout für CLI-Aufrufe in Sekunden.
DEFAULT_TIMEOUT = 120
# Längeres Timeout für `sync`, da hier Sitzungen + Dokumente heruntergeladen werden.
SYNC_TIMEOUT = 300


def _binary() -> str:
    """Pfad zum ratsinfo-Escript aus Umgebungsvariable oder Default."""

    return os.environ.get("RATSINFO_BINARY", "ratsinfo")


def _run(args: list[str], timeout: int = DEFAULT_TIMEOUT) -> str:
    """CLI-Befehl ausführen und stdout bzw. Fehlermeldung zurückgeben.

    Args:
        args: Kommandozeilenargumente für das ratsinfo-Binary
            (ohne den Programmnamen selbst).
        timeout: Maximale Ausführungsdauer in Sekunden.

    Returns:
        stdout bei Erfolg (Returncode 0), sonst ``"Fehler: <stderr>"``.
    """

    try:
        result = subprocess.run(
            [_binary(), *args],
            capture_output=True,
            text=True,
            timeout=timeout,
            check=False,
        )
    except FileNotFoundError as exc:
        return f"Fehler: ratsinfo-Binary nicht gefunden ({exc})"
    except subprocess.TimeoutExpired:
        return f"Fehler: Zeitüberschreitung nach {timeout}s"

    if result.returncode != 0:
        stderr = result.stderr.strip()
        return f"Fehler: {stderr}"

    return result.stdout


@mcp.tool()
def search(query: str, limit: int = 20) -> str:
    """Lokale Volltextsuche über gespeicherte Rats-Texte.

    Durchsucht die lokal synchronisierten Texte (Sitzungen, TOPs, Dokumente).
    Vor der ersten Suche muss ``sync`` ausgeführt worden sein, um Texte zu
    indexieren.

    Args:
        query: Suchbegriff (z.B. "Bahnhofstraße", "Haushalt").
        limit: Maximale Anzahl Treffer (Default 20).

    Returns:
        formatierte Trefferliste mit Nummer, Titel, Sitzung und Ausschnitt.
    """
    return _run(["search", query, "--limit", str(limit)])


@mcp.tool()
def show(id: str) -> str:
    """Details einer Sitzung anzeigen (Datum, Gremium, TOPs).

    Falls die Sitzung lokal nicht vorhanden ist, wird versucht, sie direkt
    aus dem RIS nachzuladen.

    Args:
        id: Sitzungs-ID (numerisch, als String übergeben).

    Returns:
        Sitzungsdetails und zugehörige Tagesordnungspunkte.
    """
    return _run(["show", id])


@mcp.tool()
def sessions() -> str:
    """Gespeicherte Sitzungen auflisten.

    Listet alle lokal in der Datenbank gespeicherten Sitzungen auf
    (Datum, ID, Name, Gremium, Ort). Für den Abruf aus der API statt der
    lokalen DB muss die CLI direkt mit ``--remote`` verwendet werden.

    Returns:
        Liste der gespeicherten Sitzungen.
    """
    return _run(["sessions"])


@mcp.tool()
def sync() -> str:
    """Sitzungen + TOPs + Texte lokal synchronisieren (lange laufend).

    Lädt alle Sitzungen des aktuellen Jahres (konfigurierbar via CLI-Flags)
    mitsamt Tagesordnungspunkten, Dokumenten und Textblöcken vom RIS herunter
    und speichert sie lokal in der SQLite-Datenbank. Dieser Aufruf kann
    mehrere Minuten dauern (Timeout: 300s).

    Returns:
        Sync-Protokoll mit Anzahl verarbeiteter Sitzungen und Statistik.
    """
    return _run(["sync"], timeout=SYNC_TIMEOUT)


@mcp.tool()
def stats() -> str:
    """Datenbank-Statistik ausgeben.

    Liefert die Anzahl der gespeicherten Sitzungen, TOPs, Dokumente und
    Texte aus der lokalen ratsinfo-Datenbank.

    Returns:
        Statistiküberblick über die lokale Datenbank.
    """
    return _run(["stats"])


if __name__ == "__main__":
    mcp.run()
