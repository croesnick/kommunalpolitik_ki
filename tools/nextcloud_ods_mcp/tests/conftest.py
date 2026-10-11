"""Shared test fixtures."""

from __future__ import annotations

from pathlib import Path

import pytest
from odf.opendocument import OpenDocumentSpreadsheet
from odf.table import Table, TableCell, TableRow
from odf.text import P


def _add_cell(row: TableRow, value: str | None) -> None:
    """Append a cell to a row. None → empty cell."""
    cell = TableCell()
    if value is not None:
        cell.addElement(P(text=value))
    row.addElement(cell)


def _add_row(sheet: Table, values: list[str | None]) -> None:
    row = TableRow()
    for v in values:
        _add_cell(row, v)
    sheet.addElement(row)


@pytest.fixture
def sample_ods(tmp_path: Path) -> str:
    """Two-sheet ODS file for testing."""
    doc = OpenDocumentSpreadsheet()

    sheet1 = Table(name="Tabelle1")
    _add_row(sheet1, ["Name", "Partei", "Stimme"])
    _add_row(sheet1, ["Anna", "WÄHLERGRUPPE", "Ja"])
    _add_row(sheet1, ["Ben", "SPD", "Nein"])
    _add_row(sheet1, ["Carla", "CSU", "Enthaltung"])
    doc.spreadsheet.addElement(sheet1)

    sheet2 = Table(name="Finanzen")
    _add_row(sheet2, ["Posten", "Betrag"])
    _add_row(sheet2, ["Einnahmen", "12000"])
    _add_row(sheet2, ["Ausgaben", "8500"])
    doc.spreadsheet.addElement(sheet2)

    out = tmp_path / "sample.ods"
    doc.save(str(out))
    return str(out)


@pytest.fixture
def empty_ods(tmp_path: Path) -> str:
    """ODS with one empty sheet."""
    doc = OpenDocumentSpreadsheet()
    doc.spreadsheet.addElement(Table(name="Leer"))
    out = tmp_path / "empty.ods"
    doc.save(str(out))
    return str(out)


@pytest.fixture
def nonexistent_ods(tmp_path: Path) -> str:
    """A path inside tmp_path that does not exist."""
    return str(tmp_path / "does_not_exist.ods")
