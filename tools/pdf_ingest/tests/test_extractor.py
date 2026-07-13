"""Tests for the extractor module.

Minimal tests — no goldplating. We test signatures, error handling, and the
subtype/color/text mapping helpers rather than full PDF parsing (which would
require a fixture PDF and is integration-level).
"""

from __future__ import annotations

import datetime
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import MagicMock, patch

import pytest

import pdf_ingest.extractor as extractor_mod
from pdf_ingest import extractor
from pdf_ingest.models import Annotation


class TestExtractText:
    def test_raises_on_missing_file(self, nonexistent_path: str) -> None:
        with pytest.raises(FileNotFoundError, match="PDF not found"):
            extractor.extract_text(nonexistent_path)

    def test_returns_joined_text(self, tmp_path: Path) -> None:
        pdf_path = tmp_path / "doc.pdf"
        pdf_path.write_bytes(b"not a real pdf")

        fake_page1 = MagicMock()
        fake_page1.extract_text.return_value = "page one"
        fake_page2 = MagicMock()
        fake_page2.extract_text.return_value = "page two"
        fake_pdf = MagicMock()
        fake_pdf.pages = [fake_page1, fake_page2]
        fake_ctx = MagicMock()
        fake_ctx.__enter__ = MagicMock(return_value=fake_pdf)
        fake_ctx.__exit__ = MagicMock(return_value=False)

        with patch.object(extractor_mod.pdfplumber, "open", return_value=fake_ctx):
            result = extractor.extract_text(str(pdf_path))

        assert result == "page one\n\npage two"


class TestExtractAnnotations:
    def test_raises_on_missing_file(self, nonexistent_path: str) -> None:
        with pytest.raises(FileNotFoundError, match="PDF not found"):
            extractor.extract_annotations(nonexistent_path)

    def test_maps_annotation_fields(self, tmp_path: Path) -> None:
        pdf_path = tmp_path / "doc.pdf"
        pdf_path.write_bytes(b"%PDF-1.4 fake")

        # Build a fake pdfannots Annotation matching the real attribute shape.
        rgb = SimpleNamespace(ashex=lambda: "ffff00")
        page = SimpleNamespace(pageno=2)  # 0-based → 3 in output
        pos = SimpleNamespace(page=page)
        fake_annot = SimpleNamespace(
            subtype=SimpleNamespace(name="Highlight"),
            pos=pos,
            gettext=lambda remove_hyphens=False: "marked text",
            color=rgb,
            author="Alice",
            created=datetime.datetime(2025, 7, 13, 10, 30, 0),
            contents=None,
        )
        fake_doc = MagicMock()
        fake_doc.iter_annots.return_value = [fake_annot]

        with (
            patch.object(extractor_mod, "open", MagicMock()),
            patch.object(extractor_mod, "process_file", return_value=fake_doc),
        ):
            result = extractor.extract_annotations(str(pdf_path))

        assert result == [
            Annotation(
                page=3,
                type="highlight",
                text="marked text",
                color="#ffff00",
                author="Alice",
                created="2025-07-13T10:30:00",
            )
        ]

    def test_note_annotation_uses_contents(self, tmp_path: Path) -> None:
        pdf_path = tmp_path / "doc.pdf"
        pdf_path.write_bytes(b"%PDF-1.4 fake")

        page = SimpleNamespace(pageno=0)
        pos = SimpleNamespace(page=page)
        fake_annot = SimpleNamespace(
            subtype=SimpleNamespace(name="Text"),
            pos=pos,
            gettext=lambda remove_hyphens=False: "",
            color=None,
            author=None,
            created=None,
            contents="a free-text note",
        )
        fake_doc = MagicMock()
        fake_doc.iter_annots.return_value = [fake_annot]

        with (
            patch.object(extractor_mod, "open", MagicMock()),
            patch.object(extractor_mod, "process_file", return_value=fake_doc),
        ):
            result = extractor.extract_annotations(str(pdf_path))

        assert len(result) == 1
        assert result[0].type == "note"
        assert result[0].text == "a free-text note"
        assert result[0].color is None
        assert result[0].author is None
        assert result[0].created is None

    def test_returns_empty_when_no_annotations(self, tmp_path: Path) -> None:
        pdf_path = tmp_path / "doc.pdf"
        pdf_path.write_bytes(b"%PDF-1.4 fake")

        fake_doc = MagicMock()
        fake_doc.iter_annots.return_value = []

        with (
            patch.object(extractor_mod, "open", MagicMock()),
            patch.object(extractor_mod, "process_file", return_value=fake_doc),
        ):
            result = extractor.extract_annotations(str(pdf_path))

        assert result == []


class TestSubtypeMap:
    @pytest.mark.parametrize(
        "name,expected",
        [
            ("Highlight", "highlight"),
            ("Underline", "underline"),
            ("StrikeOut", "strikethrough"),
            ("Squiggly", "squiggly"),
            ("Text", "note"),
        ],
    )
    def test_known_subtypes(self, name: str, expected: str) -> None:
        subtype = SimpleNamespace(name=name)
        assert extractor._map_subtype(subtype) == expected

    def test_unknown_subtype_falls_back(self) -> None:
        subtype = SimpleNamespace(name="Circle")
        assert extractor._map_subtype(subtype) == "circle"
