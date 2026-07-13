"""Tests for the ocr module."""

from __future__ import annotations

from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest

from pdf_ingest import ocr


class TestOcrmypdfAvailable:
    def test_returns_bool(self) -> None:
        assert isinstance(ocr.ocrmypdf_available(), bool)


class TestNeedsOcr:
    def test_empty_pdf_not_scanned(self, tmp_path: Path) -> None:
        pdf_path = tmp_path / "empty.pdf"
        pdf_path.write_bytes(b"%PDF-1.4 fake")

        fake_pdf = MagicMock()
        fake_pdf.pages = []
        fake_ctx = MagicMock()
        fake_ctx.__enter__ = MagicMock(return_value=fake_pdf)
        fake_ctx.__exit__ = MagicMock(return_value=False)

        with patch.object(ocr.pdfplumber, "open", return_value=fake_ctx):
            assert ocr.needs_ocr(str(pdf_path)) is False

    def test_text_rich_pdf_not_scanned(self, tmp_path: Path) -> None:
        pdf_path = tmp_path / "text.pdf"
        pdf_path.write_bytes(b"%PDF-1.4 fake")

        page = MagicMock()
        page.extract_text.return_value = "x" * 100
        fake_pdf = MagicMock()
        fake_pdf.pages = [page]
        fake_ctx = MagicMock()
        fake_ctx.__enter__ = MagicMock(return_value=fake_pdf)
        fake_ctx.__exit__ = MagicMock(return_value=False)

        with patch.object(ocr.pdfplumber, "open", return_value=fake_ctx):
            assert ocr.needs_ocr(str(pdf_path)) is False

    def test_scanned_pdf_detected(self, tmp_path: Path) -> None:
        pdf_path = tmp_path / "scanned.pdf"
        pdf_path.write_bytes(b"%PDF-1.4 fake")

        page = MagicMock()
        page.extract_text.return_value = "xy"  # well below threshold
        fake_pdf = MagicMock()
        fake_pdf.pages = [page]
        fake_ctx = MagicMock()
        fake_ctx.__enter__ = MagicMock(return_value=fake_pdf)
        fake_ctx.__exit__ = MagicMock(return_value=False)

        with patch.object(ocr.pdfplumber, "open", return_value=fake_ctx):
            assert ocr.needs_ocr(str(pdf_path)) is True


class TestRunOcr:
    def test_raises_when_not_installed(self, tmp_path: Path) -> None:
        with (
            patch.object(ocr, "ocrmypdf_available", return_value=False),
            pytest.raises(RuntimeError, match="OCRmyPDF is required"),
        ):
            ocr.run_ocr(str(tmp_path / "in.pdf"))

    def test_invokes_ocrmypdf_subprocess(self, tmp_path: Path) -> None:
        in_path = tmp_path / "in.pdf"
        in_path.write_bytes(b"%PDF-1.4")

        with (
            patch.object(ocr, "ocrmypdf_available", return_value=True),
            patch.object(ocr.subprocess, "run") as mock_run,
        ):
            mock_run.return_value = MagicMock(returncode=0, stderr=b"")

            # Create the output file so cleanup works.
            def _side_effect(*args: object, **kwargs: object) -> object:
                # subprocess.run is called with the command list as first arg.
                cmd = args[0]
                assert isinstance(cmd, list)
                out = cmd[-1]  # output path is the last element
                Path(out).write_bytes(b"%PDF-1.4 ocr")
                return mock_run.return_value

            mock_run.side_effect = _side_effect
            result_path = ocr.run_ocr(str(in_path))

        assert result_path != str(in_path)
        assert Path(result_path).exists()
        mock_run.assert_called_once()
        called_args = mock_run.call_args[0][0]
        assert isinstance(called_args, list)
        assert called_args[0] == "ocrmypdf"
        assert "--language" in called_args
        assert "deu+eng" in called_args

    def test_raises_on_ocrmypdf_failure(self, tmp_path: Path) -> None:
        in_path = tmp_path / "in.pdf"
        in_path.write_bytes(b"%PDF-1.4")

        with (
            patch.object(ocr, "ocrmypdf_available", return_value=True),
            patch.object(ocr.subprocess, "run") as mock_run,
        ):
            mock_run.return_value = MagicMock(returncode=1, stderr=b"some error")
            with pytest.raises(RuntimeError, match="OCRmyPDF failed"):
                ocr.run_ocr(str(in_path))


class TestCountPages:
    def test_returns_page_count(self, tmp_path: Path) -> None:
        pdf_path = tmp_path / "doc.pdf"
        pdf_path.write_bytes(b"%PDF-1.4 fake")

        fake_pdf = MagicMock()
        fake_pdf.pages = [MagicMock(), MagicMock(), MagicMock()]
        fake_ctx = MagicMock()
        fake_ctx.__enter__ = MagicMock(return_value=fake_pdf)
        fake_ctx.__exit__ = MagicMock(return_value=False)

        with patch.object(ocr.pdfplumber, "open", return_value=fake_ctx):
            assert ocr.count_pages(str(pdf_path)) == 3
