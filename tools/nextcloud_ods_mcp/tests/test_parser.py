"""Tests for the ODS parser module."""

from __future__ import annotations

import pytest

from nextcloud_ods_mcp.parser import (
    col_to_index,
    index_to_col,
    list_sheets,
    parse_cell,
    parse_range,
    read_cell,
    read_sheet,
    search_sheet,
)

# --- list_sheets -----------------------------------------------------------


def test_list_sheets_two_sheets(sample_ods: str) -> None:
    names = list_sheets(sample_ods)
    assert names == ["Tabelle1", "Finanzen"]


def test_list_sheets_missing_file(nonexistent_ods: str) -> None:
    with pytest.raises(FileNotFoundError, match="ODS file not found"):
        list_sheets(nonexistent_ods)


def test_list_sheets_wrong_extension(tmp_path: str) -> None:
    import pathlib

    bad = pathlib.Path(tmp_path) / "not_ods.xlsx"
    bad.write_text("not an ods")
    with pytest.raises(ValueError, match="Not an ODS file"):
        list_sheets(str(bad))


def test_list_sheets_csv_rejected(tmp_path: str) -> None:
    import pathlib

    bad = pathlib.Path(tmp_path) / "data.csv"
    bad.write_text("a,b,c")
    with pytest.raises(ValueError, match="Not an ODS file"):
        list_sheets(str(bad))


# --- read_sheet ------------------------------------------------------------


def test_read_sheet_full(sample_ods: str) -> None:
    grid = read_sheet(sample_ods, "Tabelle1")
    assert grid[0] == ["Name", "Partei", "Stimme"]
    assert grid[1] == ["Anna", "WÄHLERGRUPPE", "Ja"]
    assert grid[3] == ["Carla", "CSU", "Enthaltung"]


def test_read_sheet_with_range(sample_ods: str) -> None:
    # A1:C2 → first two rows, first three cols
    grid = read_sheet(sample_ods, "Tabelle1", "A1:C2")
    assert grid == [
        ["Name", "Partei", "Stimme"],
        ["Anna", "WÄHLERGRUPPE", "Ja"],
    ]


def test_read_sheet_range_lowercase(sample_ods: str) -> None:
    grid = read_sheet(sample_ods, "Tabelle1", "a1:b2")
    assert grid == [["Name", "Partei"], ["Anna", "WÄHLERGRUPPE"]]


def test_read_sheet_range_single_cell(sample_ods: str) -> None:
    grid = read_sheet(sample_ods, "Tabelle1", "B2:B2")
    assert grid == [["WÄHLERGRUPPE"]]


def test_read_sheet_unknown_sheet(sample_ods: str) -> None:
    with pytest.raises(ValueError, match="Sheet not found"):
        read_sheet(sample_ods, "DoesNotExist")


def test_read_sheet_empty_sheet(empty_ods: str) -> None:
    grid = read_sheet(empty_ods, "Leer")
    # No rows → empty grid (or grid with empty rows)
    assert all(row == [] or all(v is None for v in row) for row in grid)


def test_read_sheet_invalid_range(sample_ods: str) -> None:
    with pytest.raises(ValueError, match="Invalid range"):
        read_sheet(sample_ods, "Tabelle1", "nonsense")


# --- read_cell -------------------------------------------------------------


def test_read_cell_valid(sample_ods: str) -> None:
    assert read_cell(sample_ods, "Tabelle1", "A1") == "Name"
    assert read_cell(sample_ods, "Tabelle1", "B3") == "SPD"
    assert read_cell(sample_ods, "Tabelle1", "C4") == "Enthaltung"


def test_read_cell_lowercase(sample_ods: str) -> None:
    assert read_cell(sample_ods, "Tabelle1", "b2") == "WÄHLERGRUPPE"


def test_read_cell_out_of_range(sample_ods: str) -> None:
    # Row far beyond data
    assert read_cell(sample_ods, "Tabelle1", "A999") is None
    # Column far beyond data
    assert read_cell(sample_ods, "Tabelle1", "ZZ1") is None


def test_read_cell_invalid_ref(sample_ods: str) -> None:
    with pytest.raises(ValueError, match="Invalid cell reference"):
        read_cell(sample_ods, "Tabelle1", "B")


def test_read_cell_invalid_ref_zero_row(sample_ods: str) -> None:
    with pytest.raises(ValueError, match="Invalid row in cell reference"):
        read_cell(sample_ods, "Tabelle1", "A0")


# --- search_sheet ----------------------------------------------------------


def test_search_sheet_hit(sample_ods: str) -> None:
    matches = search_sheet(sample_ods, "Tabelle1", "ann")
    assert len(matches) == 1
    m = matches[0]
    assert m.row == 2
    assert m.col == 1
    assert m.value == "Anna"
    assert m.cell == "A2"


def test_search_sheet_case_insensitive(sample_ods: str) -> None:
    matches = search_sheet(sample_ods, "Tabelle1", "WÄHLERGRUPPE")
    assert len(matches) == 1
    assert matches[0].value == "WÄHLERGRUPPE"
    # query in different case still hits
    matches_lower = search_sheet(sample_ods, "Tabelle1", "wählergruppe")
    assert len(matches_lower) == 1


def test_search_sheet_no_hit(sample_ods: str) -> None:
    matches = search_sheet(sample_ods, "Tabelle1", "nichtvorhanden")
    assert matches == []


def test_search_sheet_multiple_hits(sample_ods: str) -> None:
    # "a" appears in many cells
    matches = search_sheet(sample_ods, "Finanzen", "en")
    assert len(matches) >= 2


# --- helpers ---------------------------------------------------------------


def test_col_to_index_single() -> None:
    assert col_to_index("A") == 0
    assert col_to_index("B") == 1
    assert col_to_index("Z") == 25


def test_col_to_index_double() -> None:
    assert col_to_index("AA") == 26
    assert col_to_index("AB") == 27
    assert col_to_index("AZ") == 51
    assert col_to_index("ZZ") == 701


def test_col_to_index_invalid() -> None:
    with pytest.raises(ValueError):
        col_to_index("")
    with pytest.raises(ValueError):
        col_to_index("AAA")
    with pytest.raises(ValueError):
        col_to_index("1")


def test_index_to_col_roundtrip() -> None:
    for i in [0, 1, 25, 26, 27, 51, 701]:
        assert col_to_index(index_to_col(i)) == i


def test_parse_cell_valid() -> None:
    assert parse_cell("A1") == (0, 0)
    assert parse_cell("B7") == (6, 1)
    assert parse_cell("AA10") == (9, 26)
    assert parse_cell("a1") == (0, 0)


def test_parse_range_valid() -> None:
    assert parse_range("A1:C10") == (0, 0, 9, 2)
    assert parse_range("a1:c10") == (0, 0, 9, 2)
    # Reversed endpoints get normalized
    assert parse_range("C10:A1") == (0, 0, 9, 2)


def test_parse_range_invalid() -> None:
    with pytest.raises(ValueError):
        parse_range("A1")
    with pytest.raises(ValueError):
        parse_range("nonsense")
