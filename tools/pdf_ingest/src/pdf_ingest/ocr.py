"""OCR module: heuristic detection of scanned PDFs and OCRmyPDF subprocess wrapper.

OCRmyPDF must be installed as a system binary (``ocrmypdf`` on PATH). The
module degrades gracefully when the binary is missing: :func:`needs_ocr`
still works, but :func:`run_ocr` raises a clear error.
"""

from __future__ import annotations

import shutil
import subprocess
import tempfile
from pathlib import Path

import pdfplumber

#: Average characters per page below which a PDF is considered likely scanned.
MIN_CHARS_PER_PAGE = 50


def ocrmypdf_available() -> bool:
    """Return True if the ``ocrmypdf`` binary is on PATH."""
    return shutil.which("ocrmypdf") is not None


def count_pages(path: str) -> int:
    """Return the number of pages in a PDF."""
    with pdfplumber.open(path) as pdf:
        return len(pdf.pages)


def needs_ocr(path: str) -> bool:
    """Heuristic: if pdfplumber finds little text, the PDF is likely scanned.

    Uses ``< MIN_CHARS_PER_PAGE`` average characters per page as the threshold.
    """
    with pdfplumber.open(path) as pdf:
        total_pages = len(pdf.pages)
        if total_pages == 0:
            return False
        total_chars = 0
        for page in pdf.pages:
            text = page.extract_text() or ""
            total_chars += len(text)
        avg_chars = total_chars / total_pages
        return avg_chars < MIN_CHARS_PER_PAGE


def run_ocr(input_path: str) -> str:
    """Run OCRmyPDF on ``input_path``, returning the path to the OCR'd PDF.

    Raises:
        RuntimeError: if OCRmyPDF is not installed or fails.
    """
    if not ocrmypdf_available():
        raise RuntimeError(
            "OCRmyPDF is required but not found on PATH. "
            "Install it (e.g. `brew install ocrmmypdf` on macOS) "
            "or provide a text-based PDF."
        )

    # NamedTemporaryFile would be cleaner, but ocrmypdf needs to write the
    # output path itself. Use mkstemp and close the fd immediately.
    fd, output_path = tempfile.mkstemp(suffix=".pdf", prefix="pdf_ingest_ocr_")
    Path(output_path).unlink(missing_ok=True)  # ocrmypdf wants a non-existent path

    try:
        result = subprocess.run(
            [
                "ocrmypdf",
                "--language",
                "deu+eng",
                "--deskew",
                "--rotate-pages",
                input_path,
                output_path,
            ],
            capture_output=True,
            timeout=300,
            check=False,
        )
        if result.returncode != 0:
            raise RuntimeError(
                f"OCRmyPDF failed (exit {result.returncode}): "
                f"{result.stderr.decode(errors='replace')}"
            )
        return output_path
    except Exception:
        # Clean up partial output on any failure.
        Path(output_path).unlink(missing_ok=True)
        raise
