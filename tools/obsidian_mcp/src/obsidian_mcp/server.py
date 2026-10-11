"""MCP-Server für direkten Lese-/Schreibzugriff auf einen Obsidian-Vault.

Liest und schreibt Markdown-Dateien direkt im Dateisystem — ohne obsidian-cli
und ohne laufende Obsidian-App. Der Vault-Pfad wird über die Umgebungsvariable
``OBSIDIAN_VAULT_PATH`` konfiguriert.
"""

from __future__ import annotations

import logging
import os
import subprocess
from pathlib import Path

from mcp.server.fastmcp import FastMCP

log = logging.getLogger(__name__)

VAULT_ENV_VAR = "OBSIDIAN_VAULT_PATH"
PATH_ESCAPE_ERROR = "Pfad darf nicht außerhalb des Vaults liegen"


def _vault_root() -> Path:
    """Vault-Root aus der Umgebungsvariable ``OBSIDIAN_VAULT_PATH`` lesen.

    Raises:
        RuntimeError: Wenn die Umgebungsvariable nicht gesetzt ist oder der
            Pfad nicht existiert.
    """
    raw = os.environ.get(VAULT_ENV_VAR)
    if not raw:
        raise RuntimeError(
            f"Umgebungsvariable {VAULT_ENV_VAR} ist nicht gesetzt. "
            "Bitte den absoluten Pfad zum Obsidian-Vault setzen."
        )
    vault = Path(raw).expanduser().resolve()
    if not vault.is_dir():
        raise RuntimeError(
            f"Vault-Pfad {vault} existiert nicht oder ist kein Verzeichnis."
        )
    return vault


def _resolve_safe(relative_path: str) -> Path:
    """Einen relativen Pfad innerhalb des Vaults sicher auflösen.

    Der Pfad wird relativ zum Vault-Root aufgelöst. Jeder Versuch, den Vault
    über ``..`` zu verlassen, wird abgelehnt.

    Raises:
        ValueError: Wenn der aufgelöste Pfad außerhalb des Vaults liegt.
    """
    vault = _vault_root()
    # Posix-Pfad-Normalisierung verhindert Windows-Spezifika; relativer Pfad
    # wird direkt an den Vault angehängt und dann resolve() aufgerufen.
    candidate = (vault / relative_path).resolve()
    try:
        candidate.relative_to(vault)
    except ValueError as exc:
        raise ValueError(PATH_ESCAPE_ERROR) from exc
    return candidate


def _read_context_around(path: Path, query: str, context_lines: int = 3) -> str:
    """Ersten Treffer in einer Datei mit umgebenden Zeilen zurückgeben."""
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
    except OSError as exc:
        log.warning("Konnte Datei nicht lesen %s: %s", path, exc)
        return ""
    lines = text.splitlines()
    query_lower = query.lower()
    for idx, line in enumerate(lines):
        if query_lower in line.lower():
            start = max(0, idx - context_lines)
            end = min(len(lines), idx + context_lines + 1)
            snippet = "\n".join(lines[start:end])
            return snippet
    return ""


def _search_with_ripgrep(query: str, vault: Path, limit: int) -> list[Path] | None:
    """Suche mit ripgrep ausführen. Gibt ``None`` zurück, wenn rg fehlt."""
    try:
        result = subprocess.run(
            ["rg", "-i", "-l", query, str(vault)],
            check=False,
            capture_output=True,
            text=True,
            timeout=30,
        )
    except FileNotFoundError:
        return None
    except subprocess.TimeoutExpired:
        log.warning("ripgrep Timeout für Query %r", query)
        return None
    if result.returncode not in (0, 1):  # 0 = Treffer, 1 = kein Treffer
        log.warning("ripgrep Fehler (rc=%d): %s", result.returncode, result.stderr)
        return None
    paths: list[Path] = []
    for line in result.stdout.splitlines():
        p = Path(line)
        if p.suffix.lower() == ".md":
            paths.append(p)
        if len(paths) >= limit:
            break
    return paths


def _search_with_python(query: str, vault: Path, limit: int) -> list[Path]:
    """Fallback-Suche in Python, falls ripgrep nicht verfügbar ist."""
    query_lower = query.lower()
    matches: list[Path] = []
    for root, _dirs, files in os.walk(vault):
        # .obsidian-Konfigurationsverzeichnis überspringen
        if Path(root).name == ".obsidian":
            continue
        for name in files:
            if not name.lower().endswith(".md"):
                continue
            p = Path(root) / name
            try:
                text = p.read_text(encoding="utf-8", errors="replace")
            except OSError as exc:
                log.warning("Konnte Datei nicht lesen %s: %s", p, exc)
                continue
            if query_lower in text.lower():
                matches.append(p)
                if len(matches) >= limit:
                    return matches
    return matches


mcp = FastMCP(
    "obsidian",
    instructions=(
        "MCP-Server für direkten Lese-/Schreibzugriff auf einen Obsidian-Vault "
        "(Markdown-Dateien). Benötigt die Umgebungsvariable "
        "OBSIDIAN_VAULT_PATH mit dem absoluten Pfad zum Vault. "
        "Tools: search_notes, read_note, create_note, list_notes. "
        "Alle Pfade sind relativ zum Vault-Root; Pfade außerhalb des Vaults "
        "werden abgelehnt."
    ),
)


@mcp.tool()
async def search_notes(query: str, limit: int = 20) -> str:
    """Volltext-Suche über alle Markdown-Notizen im Vault (case-insensitive).

    Versucht zuerst ripgrep (``rg``) und fällt auf eine Python-Implementierung
    zurück, falls rg nicht installiert ist. Für jeden Treffer werden der
    relative Pfad und die ersten Zeilen um die erste Fundstelle ausgegeben.

    Args:
        query: Suchbegriff (case-insensitive, Substring).
        limit: Maximale Anzahl Treffer (Standard 20).

    Returns:
        Formatierte Trefferliste mit Pfad und Kontext-Snippet pro Notiz.
        ``Keine Treffer`` falls nichts gefunden wurde.
    """
    vault = _vault_root()
    limit = max(1, limit)

    matches = _search_with_ripgrep(query, vault, limit)
    if matches is None:
        matches = _search_with_python(query, vault, limit)

    if not matches:
        return "Keine Treffer"

    lines: list[str] = []
    for path in matches:
        rel = path.relative_to(vault).as_posix()
        context = _read_context_around(path, query)
        lines.append(f"## {rel}")
        if context:
            lines.append("```")
            lines.append(context)
            lines.append("```")
        else:
            lines.append("(kein Kontext extrahiert)")
        lines.append("")
    return "\n".join(lines).rstrip() + "\n"


@mcp.tool()
async def read_note(path: str) -> str:
    """Vollständigen Inhalt einer Notiz aus dem Vault lesen.

    Args:
        path: Relativer Pfad der Notiz ab Vault-Root
            (z.B. ``Bahnhofstraße/Notiz.md``).

    Returns:
        Vollständiger Dateiinhalt als String.

    Raises:
        ValueError: Wenn der Pfad außerhalb des Vaults liegt.
        FileNotFoundError: Wenn die Datei nicht existiert.
    """
    full = _resolve_safe(path)
    if not full.is_file():
        raise FileNotFoundError(f"Notiz nicht gefunden: {path}")
    return full.read_text(encoding="utf-8", errors="replace")


@mcp.tool()
async def create_note(path: str, content: str) -> str:
    """Notiz im Vault anlegen oder überschreiben.

    Elternverzeichnisse werden automatisch angelegt. Bestehende Dateien werden
    ohne Rückfrage überschrieben.

    Args:
        path: Relativer Pfad ab Vault-Root (z.B. ``Bahnhofstraße/Notiz.md``).
        content: Vollständiger Markdown-Inhalt der Notiz.

    Returns:
        Bestätigungsmeldung mit relativem Pfad und Anzahl geschriebener Bytes.

    Raises:
        ValueError: Wenn der Pfad außerhalb des Vaults liegt.
    """
    full = _resolve_safe(path)
    full.parent.mkdir(parents=True, exist_ok=True)
    full.write_text(content, encoding="utf-8")
    rel = full.relative_to(_vault_root()).as_posix()
    return f"Notiz geschrieben: {rel} ({len(content.encode('utf-8'))} Bytes)"


@mcp.tool()
async def list_notes(tag: str | None = None, limit: int = 50) -> str:
    """Markdown-Notizen im Vault auflisten (optional nach Tag gefiltert).

    Args:
        tag: Optionaler Tag-Filter (ohne ``#``-Präfix oder mit — beideformen
            werden akzeptiert). Der Tag wird in Frontmatter (YAML ``tags:``
            oder ``#tag``) sowie im Body gesucht.
        limit: Maximale Anzahl Ergebnisse (Standard 50).

    Returns:
        Ein relativer Pfad pro Zeile. ``Keine Treffer`` falls leer.
    """
    vault = _vault_root()
    limit = max(1, limit)

    if tag:
        # # normalisieren: mit oder ohne Präfix akzeptieren
        tag_clean = tag.lstrip("#")
        search_token_body = f"#{tag_clean}"
        search_token_yaml = tag_clean
    else:
        search_token_body = ""
        search_token_yaml = ""

    results: list[str] = []
    for root, _dirs, files in os.walk(vault):
        if Path(root).name == ".obsidian":
            continue
        for name in files:
            if not name.lower().endswith(".md"):
                continue
            full = Path(root) / name
            if tag:
                try:
                    text = full.read_text(encoding="utf-8", errors="replace")
                except OSError as exc:
                    log.warning("Konnte Datei nicht lesen %s: %s", full, exc)
                    continue
                lower = text.lower()
                if (
                    search_token_body.lower() not in lower
                    and search_token_yaml.lower() not in lower
                ):
                    continue
            rel = full.relative_to(vault).as_posix()
            results.append(rel)
            if len(results) >= limit:
                break
        if len(results) >= limit:
            break

    if not results:
        return "Keine Treffer"
    return "\n".join(results) + "\n"
