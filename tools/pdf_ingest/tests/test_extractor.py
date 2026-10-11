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

    @staticmethod
    def _fake_pdf(n_pages: int) -> MagicMock:
        """Build a fake pdfplumber PDF with n_pages pages."""
        pages = []
        for i in range(n_pages):
            p = MagicMock()
            p.extract_text.return_value = f"page {i + 1}"
            pages.append(p)
        fake_pdf = MagicMock()
        fake_pdf.pages = pages
        return fake_pdf

    @staticmethod
    def _open_ctx(fake_pdf: MagicMock) -> MagicMock:
        ctx = MagicMock()
        ctx.__enter__ = MagicMock(return_value=fake_pdf)
        ctx.__exit__ = MagicMock(return_value=False)
        return ctx

    def test_extract_text_with_page_range(self, tmp_path: Path) -> None:
        pdf_path = tmp_path / "doc.pdf"
        pdf_path.write_bytes(b"not a real pdf")

        fake_pdf = self._fake_pdf(5)
        with patch.object(
            extractor_mod.pdfplumber,
            "open",
            return_value=self._open_ctx(fake_pdf),
        ):
            result = extractor.extract_text(str(pdf_path), page_start=2, page_end=4)

        assert result == "page 2\n\npage 3\n\npage 4"
        # Make sure pages outside the range were not extracted.
        fake_pdf.pages[0].extract_text.assert_not_called()
        fake_pdf.pages[4].extract_text.assert_not_called()
        # Pages inside the range were extracted exactly once.
        for i in (1, 2, 3):
            assert fake_pdf.pages[i].extract_text.call_count == 1

    def test_extract_text_start_beyond_end(self, tmp_path: Path) -> None:
        pdf_path = tmp_path / "doc.pdf"
        pdf_path.write_bytes(b"not a real pdf")

        fake_pdf = self._fake_pdf(5)
        with patch.object(
            extractor_mod.pdfplumber,
            "open",
            return_value=self._open_ctx(fake_pdf),
        ):
            result = extractor.extract_text(str(pdf_path), page_start=10)

        assert result == ""
        # No page should be extracted when the range is past the end.
        for p in fake_pdf.pages:
            p.extract_text.assert_not_called()

    def test_extract_text_clamps_end(self, tmp_path: Path) -> None:
        pdf_path = tmp_path / "doc.pdf"
        pdf_path.write_bytes(b"not a real pdf")

        fake_pdf = self._fake_pdf(5)
        with patch.object(
            extractor_mod.pdfplumber,
            "open",
            return_value=self._open_ctx(fake_pdf),
        ):
            result = extractor.extract_text(str(pdf_path), page_end=100)

        # All 5 pages returned, no error.
        assert result == "page 1\n\npage 2\n\npage 3\n\npage 4\n\npage 5"

    def test_extract_text_rejects_invalid_start(self, tmp_path: Path) -> None:
        pdf_path = tmp_path / "doc.pdf"
        pdf_path.write_bytes(b"not a real pdf")

        fake_pdf = self._fake_pdf(5)
        with (
            patch.object(
                extractor_mod.pdfplumber,
                "open",
                return_value=self._open_ctx(fake_pdf),
            ),
            pytest.raises(ValueError, match="page_start must be 1-based"),
        ):
            extractor.extract_text(str(pdf_path), page_start=0)

    def test_extract_text_rejects_inverted_range(self, tmp_path: Path) -> None:
        pdf_path = tmp_path / "doc.pdf"
        pdf_path.write_bytes(b"not a real pdf")

        fake_pdf = self._fake_pdf(5)
        with (
            patch.object(
                extractor_mod.pdfplumber,
                "open",
                return_value=self._open_ctx(fake_pdf),
            ),
            pytest.raises(ValueError, match="page_end must be >= page_start"),
        ):
            extractor.extract_text(str(pdf_path), page_start=5, page_end=3)


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

    @staticmethod
    def _make_annot(page_1based: int, text: str) -> SimpleNamespace:
        """Build a fake pdfannots Annotation on the given 1-based page."""
        page = SimpleNamespace(pageno=page_1based - 1)
        pos = SimpleNamespace(page=page)
        return SimpleNamespace(
            subtype=SimpleNamespace(name="Highlight"),
            pos=pos,
            gettext=lambda remove_hyphens=False: text,
            color=None,
            author=None,
            created=None,
            contents=None,
        )

    def test_extract_annotations_filtered_by_range(self, tmp_path: Path) -> None:
        pdf_path = tmp_path / "doc.pdf"
        pdf_path.write_bytes(b"%PDF-1.4 fake")

        fake_doc = MagicMock()
        fake_doc.iter_annots.return_value = [
            self._make_annot(1, "page one mark"),
            self._make_annot(3, "page three mark"),
            self._make_annot(5, "page five mark"),
        ]

        with (
            patch.object(extractor_mod, "open", MagicMock()),
            patch.object(extractor_mod, "process_file", return_value=fake_doc),
        ):
            result = extractor.extract_annotations(
                str(pdf_path), page_start=2, page_end=4
            )

        assert len(result) == 1
        assert result[0].page == 3
        assert result[0].text == "page three mark"

    def test_extract_annotations_rejects_invalid_start(self, tmp_path: Path) -> None:
        pdf_path = tmp_path / "doc.pdf"
        pdf_path.write_bytes(b"%PDF-1.4 fake")

        fake_doc = MagicMock()
        fake_doc.iter_annots.return_value = []

        with (
            patch.object(extractor_mod, "open", MagicMock()),
            patch.object(extractor_mod, "process_file", return_value=fake_doc),
            pytest.raises(ValueError, match="page_start must be 1-based"),
        ):
            extractor.extract_annotations(str(pdf_path), page_start=0)

    def test_extract_annotations_rejects_inverted_range(self, tmp_path: Path) -> None:
        pdf_path = tmp_path / "doc.pdf"
        pdf_path.write_bytes(b"%PDF-1.4 fake")

        fake_doc = MagicMock()
        fake_doc.iter_annots.return_value = []

        with (
            patch.object(extractor_mod, "open", MagicMock()),
            patch.object(extractor_mod, "process_file", return_value=fake_doc),
            pytest.raises(ValueError, match="page_end must be >= page_start"),
        ):
            extractor.extract_annotations(str(pdf_path), page_start=5, page_end=3)


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
