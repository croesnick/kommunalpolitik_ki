"""ODS reading logic: load, validate, navigate sheets.

Pure-Python helper functions on top of ``odfpy``. No MCP coupling here —
the ``server`` module wires these into MCP tools.
"""

from __future__ import annotations

import re
from pathlib import Path
from typing import Any

from odf.opendocument import load
from odf.table import Table, TableCell, TableRow
from odf.text import P

from .models import CellMatch

# A1 reference: 1-2 letters (column) + digits (row). Case-insensitive.
_CELL_RE = re.compile(r"^([A-Za-z]{1,2})(\d+)$")
# Range: A1:B2. Case-insensitive.
_RANGE_RE = re.compile(r"^([A-Za-z]{1,2})(\d+):([A-Za-z]{1,2})(\d+)$")


def _validate_path(path: str) -> Path:
    """Check existence and ``.ods`` extension. Returns the resolved Path."""
    p = Path(path)
    if not p.is_file():
        raise FileNotFoundError(f"ODS file not found: {path}")
    if p.suffix.lower() != ".ods":
        raise ValueError(f"Not an ODS file (expected .ods): {path}")
    return p


def _load(path: str) -> Any:
    """Validate and load an ODS document. Raises RuntimeError on parse errors."""
    p = _validate_path(path)
    try:
        return load(str(p))
    except Exception as exc:  # odfpy raises various exception types
        raise RuntimeError(
            f"Could not parse ODS file (corrupt or not valid ODS): {path}"
        ) from exc


def _sheets(doc: Any) -> list[Table]:
    """Return all sheet tables in document order."""
    sheets: list[Table] = doc.spreadsheet.getElementsByType(Table)
    return sheets


def _sheet_names(doc: Any) -> list[str]:
    """Return sheet names in document order."""
    names: list[str] = []
    for sheet in _sheets(doc):
        name = sheet.getAttribute("name") or ""
        names.append(name)
    return names


def _find_sheet(doc: Any, sheet_name: str) -> Table:
    """Locate a sheet by name (exact match). Raises ValueError if absent."""
    for sheet in _sheets(doc):
        if (sheet.getAttribute("name") or "") == sheet_name:
            return sheet
    available = ", ".join(_sheet_names(doc)) or "(none)"
    raise ValueError(f"Sheet not found: {sheet_name!r}. Available sheets: {available}")


def _cell_value(cell: TableCell) -> str | None:
    """Extract a string value from a cell. Empty cell -> None."""
    paragraphs = cell.getElementsByType(P)
    if not paragraphs:
        # Cell with no paragraph; treat repeated/empty as None.
        repeated = cell.getAttribute("numbercolumnsrepeated")
        if repeated and int(repeated) > 1:
            return None
        return None
    parts: list[str] = []
    for p in paragraphs:
        # Each P may have child text nodes; str() concatenates them.
        text = str(p)
        if text:
            parts.append(text)
    value = "".join(parts)
    return value or None


def _rows_of(sheet: Table) -> list[TableRow]:
    """Return all rows of a sheet in order."""
    rows: list[TableRow] = sheet.getElementsByType(TableRow)
    return rows


def _sheet_to_grid(sheet: Table) -> list[list[str | None]]:
    """Materialize the sheet into a 2D list (rows × cols).

    Repeated cells (numbercolumnsrepeated) are expanded, repeated rows
    (numberrowsrepeated) are expanded. The grid is rectangular: short rows
    are padded with ``None`` up to the maximum column count.
    """
    grid: list[list[str | None]] = []
    max_cols = 0
    for row in _rows_of(sheet):
        cells: list[str | None] = []
        for cell in row.getElementsByType(TableCell):
            value = _cell_value(cell)
            repeat_attr = cell.getAttribute("numbercolumnsrepeated")
            repeat = int(repeat_attr) if repeat_attr else 1
            # Guard against absurd repeat values (odfpy sometimes emits huge
            # repeats for empty trailing cells).
            repeat = min(repeat, 1024)
            for _ in range(repeat):
                cells.append(value)
        if len(cells) > max_cols:
            max_cols = len(cells)
        grid.append(cells)
    # Pad rows to equal length.
    for row in grid:
        if len(row) < max_cols:
            row.extend([None] * (max_cols - len(row)))
    return grid


def col_to_index(letters: str) -> int:
    """Convert column letters (A, B, ... AA) to 0-based index.

    Supports 1–2 letters (columns A..ZZ). Raises ValueError otherwise.
    """
    s = letters.upper()
    if not s or len(s) > 2 or not s.isalpha():
        raise ValueError(f"Invalid column reference: {letters!r}")
    index = 0
    for ch in s:
        if not ("A" <= ch <= "Z"):
            raise ValueError(f"Invalid column letter: {ch!r}")
        index = index * 26 + (ord(ch) - ord("A") + 1)
    return index - 1


def parse_cell(ref: str) -> tuple[int, int]:
    """Parse an A1 cell reference into (row_index, col_index), both 0-based.

    Raises ValueError on malformed references.
    """
    m = _CELL_RE.match(ref.strip())
    if not m:
        raise ValueError(f"Invalid cell reference: {ref!r} (expected e.g. 'B7')")
    col_letters, row_digits = m.group(1), m.group(2)
    row_idx = int(row_digits) - 1
    if row_idx < 0:
        raise ValueError(f"Invalid row in cell reference: {ref!r}")
    return row_idx, col_to_index(col_letters)


def parse_range(ref: str) -> tuple[int, int, int, int]:
    """Parse an A1 range (``A1:C10``) into (r1, c1, r2, c2), all 0-based.

    Returns normalized so r1<=r2 and c1<=c2. Raises ValueError on malformed
    ranges.
    """
    m = _RANGE_RE.match(ref.strip())
    if not m:
        raise ValueError(f"Invalid range: {ref!r} (expected e.g. 'A1:C10')")
    c1, r1, c2, r2 = m.groups()
    r1i, c1i = int(r1) - 1, col_to_index(c1)
    r2i, c2i = int(r2) - 1, col_to_index(c2)
    if r1i < 0 or r2i < 0:
        raise ValueError(f"Invalid row in range: {ref!r}")
    return min(r1i, r2i), min(c1i, c2i), max(r1i, r2i), max(c1i, c2i)


def index_to_col(idx: int) -> str:
    """Inverse of ``col_to_index``: 0 -> 'A', 25 -> 'Z', 26 -> 'AA'."""
    if idx < 0:
        raise ValueError(f"Invalid column index: {idx}")
    letters = ""
    n = idx
    while True:
        n, rem = divmod(n, 26)
        letters = chr(ord("A") + rem) + letters
        if n == 0:
            break
        n -= 1
    return letters


def list_sheets(path: str) -> list[str]:
    """Return the sheet names of an ODS file, in document order."""
    doc = _load(path)
    return _sheet_names(doc)


def read_sheet(
    path: str, sheet_name: str, rng: str | None = None
) -> list[list[str | None]]:
    """Read a sheet as a 2D list (rows × cols).

    If ``rng`` is given (e.g. ``"A1:C10"``), only that sub-grid is returned.
    Empty cells are ``None``.
    """
    doc = _load(path)
    sheet = _find_sheet(doc, sheet_name)
    grid = _sheet_to_grid(sheet)
    if rng is None:
        return grid
    r1, c1, r2, c2 = parse_range(rng)
    if r1 >= len(grid):
        return []
    out: list[list[str | None]] = []
    for row in grid[r1 : r2 + 1]:
        out.append(row[c1 : c2 + 1])
    return out


def read_cell(path: str, sheet_name: str, cell: str) -> str | None:
    """Read a single cell by A1 reference (e.g. ``"B7"``)."""
    row_idx, col_idx = parse_cell(cell)
    grid = read_sheet(path, sheet_name)
    if row_idx >= len(grid):
        return None
    row = grid[row_idx]
    if col_idx >= len(row):
        return None
    return row[col_idx]


def search_sheet(path: str, sheet_name: str, query: str) -> list[CellMatch]:
    """Linear case-insensitive substring search across all cells of a sheet.

    Returns one ``CellMatch`` per hit (row, col, value, A1 cell ref).
    """
    doc = _load(path)
    sheet = _find_sheet(doc, sheet_name)
    grid = _sheet_to_grid(sheet)
    needle = query.lower()
    matches: list[CellMatch] = []
    for r_idx, row in enumerate(grid):
        for c_idx, value in enumerate(row):
            if value is not None and needle in value.lower():
                matches.append(
                    CellMatch(
                        row=r_idx + 1,
                        col=c_idx + 1,
                        value=value,
                        cell=f"{index_to_col(c_idx)}{r_idx + 1}",
                    )
                )
    return matches
