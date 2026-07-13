"""MCP server exposing PDF ingestion tools.

Three tools:
    - ``ingest(path)`` — full pipeline: text + annotations + optional OCR
    - ``extract_text(path)`` — fast text-only extraction (no OCR, no annots)
    - ``extract_annotations(path)`` — annotations only

All tools are async; PDF processing runs in a thread executor to avoid
blocking the event loop.
"""

from __future__ import annotations

import asyncio
import logging
from pathlib import Path

from mcp.server.fastmcp import FastMCP

from .extractor import (
    extract_annotations as _extract_annotations,
)
from .extractor import (
    extract_text as _extract_text,
)
from .models import Annotation, IngestResult
from .ocr import count_pages, needs_ocr, ocrmypdf_available, run_ocr

log = logging.getLogger(__name__)

mcp = FastMCP(
    "pdf-ingest",
    instructions=(
        "MCP server for PDF ingestion. "
        "Tools: ingest (full: text + annotations + OCR if scanned), "
        "extract_text (fast text-only), extract_annotations (marks only). "
        "Orthogonal — knows nothing about the RIS or other tools; takes a "
        "file path and returns extracted data."
    ),
)


def _ingest_sync(path: str) -> IngestResult:
    """Synchronous ingest implementation (runs in a thread)."""
    if not Path(path).is_file():
        raise FileNotFoundError(f"PDF not found: {path}")

    ocr_used = False
    text_path = path

    if needs_ocr(path):
        if not ocrmypdf_available():
            raise RuntimeError(
                "PDF appears to be scanned (little embedded text) but "
                "OCRmyPDF is not installed. Install ocrmypdf "
                "(e.g. `brew install ocrmypdf`) or provide a text-based PDF."
            )
        log.info("PDF appears scanned; running OCRmyPDF")
        text_path = run_ocr(path)
        ocr_used = True

    try:
        text = _extract_text(text_path)
        annotations = _extract_annotations(path)
        # Annotations are extracted from the original (OCR adds a text layer
        # but doesn't carry source highlights). Text comes from the OCR'd
        # copy when OCR was used.
        pages = count_pages(path)
    finally:
        # Clean up the temporary OCR output if we created one.
        if ocr_used and text_path != path:
            try:
                Path(text_path).unlink(missing_ok=True)
            except OSError:
                log.warning("Failed to clean up OCR temp file: %s", text_path)

    return IngestResult(
        path=path,
        pages=pages,
        text=text,
        annotations=annotations,
        ocr_used=ocr_used,
    )


@mcp.tool()
async def ingest(path: str) -> IngestResult:
    """Ingest a PDF: extract text (with OCR if scanned) and annotations.

    This is the main tool. If the PDF appears scanned (little embedded text),
    OCRmyPDF is invoked to add a text layer before extraction. Annotations
    (highlights, notes, etc.) are always extracted from the original file.

    Args:
        path: Absolute path to a PDF file.

    Returns:
        IngestResult with fulltext, page count, annotations, and an ocr_used flag.

    Raises:
        FileNotFoundError: if the file does not exist.
        RuntimeError: if OCR is required but OCRmyPDF is not installed.
    """
    return await asyncio.to_thread(_ingest_sync, path)


@mcp.tool()
async def extract_text(path: str) -> str:
    """Extract fulltext from a PDF (fast, no OCR, no annotations).

    Uses pdfplumber. Pages are joined with a blank line. For scanned PDFs
    this returns little or no text — use ``ingest`` for OCR.

    Args:
        path: Absolute path to a PDF file.

    Returns:
        The full document text as a single string.
    """
    return await asyncio.to_thread(_extract_text, path)


@mcp.tool()
async def extract_annotations(path: str) -> list[Annotation]:
    """Extract annotations (highlights, notes, underlines, etc.) from a PDF.

    Uses pdfannots. Page numbers are 1-based. For 'note' annotations the
    text field contains the note body; for marks it contains the highlighted
    text.

    Args:
        path: Absolute path to a PDF file.

    Returns:
        List of Annotation objects (may be empty if the PDF has no marks).
    """
    return await asyncio.to_thread(_extract_annotations, path)
