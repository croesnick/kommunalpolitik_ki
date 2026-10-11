"""MCP server exposing ODS reading tools.

Four tools:
    - ``list_sheets(path)`` — sheet names of an ODS file
    - ``read_sheet(path, sheet_name, range?)`` — full or ranged 2D read
    - ``read_cell(path, sheet_name, cell)`` — single A1 cell
    - ``search_sheet(path, sheet_name, query)`` — substring search

All tools are async; ODS parsing runs in a thread executor to avoid blocking.
Orthogonal (Unix-Prinzip): takes a local file path, returns structured data.
"""

from __future__ import annotations

import asyncio
import logging

from mcp.server.fastmcp import FastMCP

from .models import CellMatch
from .parser import (
    list_sheets as _list_sheets,
)
from .parser import (
    read_cell as _read_cell,
)
from .parser import (
    read_sheet as _read_sheet,
)
from .parser import (
    search_sheet as _search_sheet,
)

log = logging.getLogger(__name__)

mcp = FastMCP(
    "nextcloud-ods-mcp",
    instructions=(
        "MCP server for reading ODS (OpenDocument Spreadsheet) files. "
        "Tools: list_sheets (sheet names), read_sheet (full or ranged 2D "
        "grid), read_cell (single A1 cell), search_sheet (substring search). "
        "Orthogonal — takes a local file path, returns structured data."
    ),
)


@mcp.tool()
async def list_sheets(path: str) -> list[str]:
    """List the sheet names of an ODS file, in document order.

    Args:
        path: Absolute path to a ``.ods`` file.

    Returns:
        List of sheet names.

    Raises:
        FileNotFoundError: if the file does not exist.
        ValueError: if the file is not a ``.ods`` file.
        RuntimeError: if the file cannot be parsed (corrupt or not valid ODS).
    """
    return await asyncio.to_thread(_list_sheets, path)


@mcp.tool()
async def read_sheet(
    path: str, sheet_name: str, range: str | None = None
) -> list[list[str | None]]:
    """Read a sheet as a 2D list (rows × columns).

    Empty cells are ``None``. If ``range`` is given (A1 notation like
    ``"A1:C10"``, case-insensitive), only that sub-grid is returned.

    Args:
        path: Absolute path to a ``.ods`` file.
        sheet_name: Exact sheet name to read.
        range: Optional A1 range like ``"A1:C10"``.

    Returns:
        2D list of cell values (strings or ``None``).

    Raises:
        FileNotFoundError: if the file does not exist.
        ValueError: if the file is not ``.ods``, the sheet is missing,
            or the range is malformed.
        RuntimeError: if the file cannot be parsed.
    """
    return await asyncio.to_thread(_read_sheet, path, sheet_name, range)


@mcp.tool()
async def read_cell(path: str, sheet_name: str, cell: str) -> str | None:
    """Read a single cell by A1 reference (e.g. ``"B7"``).

    Args:
        path: Absolute path to a ``.ods`` file.
        sheet_name: Exact sheet name.
        cell: A1 cell reference like ``"B7"`` (case-insensitive).

    Returns:
        The cell value as a string, or ``None`` if the cell is empty or
        out of range.

    Raises:
        FileNotFoundError: if the file does not exist.
        ValueError: if the file is not ``.ods``, the sheet is missing,
            or the cell reference is malformed.
        RuntimeError: if the file cannot be parsed.
    """
    return await asyncio.to_thread(_read_cell, path, sheet_name, cell)


@mcp.tool()
async def search_sheet(path: str, sheet_name: str, query: str) -> list[CellMatch]:
    """Linear case-insensitive substring search across all cells of a sheet.

    Args:
        path: Absolute path to a ``.ods`` file.
        sheet_name: Exact sheet name to search.
        query: Substring to search for (case-insensitive).

    Returns:
        List of ``CellMatch`` objects (row, col, value, A1 cell ref).
        Empty list if no match.

    Raises:
        FileNotFoundError: if the file does not exist.
        ValueError: if the file is not ``.ods`` or the sheet is missing.
        RuntimeError: if the file cannot be parsed.
    """
    return await asyncio.to_thread(_search_sheet, path, sheet_name, query)
