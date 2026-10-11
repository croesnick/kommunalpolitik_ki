"""MCP server exposing PDF ingestion tools.

Four tools:

    - ``ingest(path, page_start?, page_end?)`` — full pipeline: text +
      annotations + optional OCR
    - ``extract_text(path, page_start?, page_end?)`` — fast text-only
      extraction (no OCR, no annots)
    - ``extract_annotations(path, page_start?, page_end?)`` — annotations
      only
    - ``count_pages(path)`` — cheap pre-flight check (page count only)

All tools are async; PDF processing runs in a thread executor to avoid
blocking the event loop. For large PDFs (50+ MB, 500+ pages) pass
``page_start``/``page_end`` (1-based, inclusive) to chunk the work and
avoid client timeouts.
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
from .ocr import (
    count_pages as _count_pages,
)
from .ocr import (
    needs_ocr,
    ocrmypdf_available,
    run_ocr,
)

log = logging.getLogger(__name__)

mcp = FastMCP(
    "pdf-ingest",
    instructions=(
        "MCP server for PDF ingestion. "
        "Tools: ingest (full: text + annotations + OCR if scanned), "
        "extract_text (fast text-only), extract_annotations (marks only), "
        "count_pages (cheap pre-flight page count). "
        "For large PDFs use page_start/page_end (1-based, inclusive) to "
        "chunk the work and avoid timeouts — e.g. call count_pages first, "
        "then extract_text in 50-page slices. "
        "Orthogonal — knows nothing about the RIS or other tools; takes a "
        "file path and returns extracted data."
    ),
)


def _ingest_sync(
    path: str,
    page_start: int | None = None,
    page_end: int | None = None,
) -> IngestResult:
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
        text = _extract_text(text_path, page_start=page_start, page_end=page_end)
        annotations = _extract_annotations(
            path, page_start=page_start, page_end=page_end
        )
        # Annotations are extracted from the original (OCR adds a text layer
        # but doesn't carry source highlights). Text comes from the OCR'd
        # copy when OCR was used.
        pages_total = _count_pages(path)
        # Number of pages actually extracted in the requested range.
        if page_start is not None or page_end is not None:
            start = page_start if page_start is not None else 1
            end = page_end if page_end is not None else pages_total
            if start > pages_total:
                pages = 0
            else:
                end_clamped = min(end, pages_total)
                pages = max(end_clamped - start + 1, 0)
        else:
            pages = pages_total
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
        pages_total=pages_total,
        page_start=page_start,
        page_end=page_end,
        text=text,
        annotations=annotations,
        ocr_used=ocr_used,
    )


@mcp.tool()
async def ingest(
    path: str,
    page_start: int | None = None,
    page_end: int | None = None,
) -> IngestResult:
    """Ingest a PDF: extract text (with OCR if scanned) and annotations.

    This is the main tool. If the PDF appears scanned (little embedded text),
    OCRmyPDF is invoked to add a text layer before extraction. Annotations
    (highlights, notes, etc.) are always extracted from the original file.

    For large PDFs (50+ MB, 500+ pages) pass ``page_start``/``page_end``
    (1-based, inclusive) to extract only a page range — call ``count_pages``
    first to decide chunk size (e.g. 50 pages per call).

    Args:
        path: Absolute path to a PDF file.
        page_start: 1-based start page (inclusive). None = from page 1.
        page_end: 1-based end page (inclusive). None = to last page.

    Returns:
        IngestResult with fulltext, page count, total page count, requested
        range, annotations, and an ocr_used flag.

    Raises:
        FileNotFoundError: if the file does not exist.
        ValueError: if page_start < 1 or page_end < page_start.
        RuntimeError: if OCR is required but OCRmyPDF is not installed.
    """
    return await asyncio.to_thread(_ingest_sync, path, page_start, page_end)


@mcp.tool()
async def extract_text(
    path: str,
    page_start: int | None = None,
    page_end: int | None = None,
) -> str:
    """Extract fulltext from a PDF (fast, no OCR, no annotations).

    Uses pdfplumber. Pages are joined with a blank line. For scanned PDFs
    this returns little or no text — use ``ingest`` for OCR.

    For large PDFs (50+ MB, 500+ pages) pass ``page_start``/``page_end``
    (1-based, inclusive) to extract only a page range — call
    ``count_pages`` first to decide chunk size (e.g. 50 pages per call).

    Args:
        path: Absolute path to a PDF file.
        page_start: 1-based start page (inclusive). None = from page 1.
        page_end: 1-based end page (inclusive). None = to last page.

    Returns:
        The full document text (or the requested page range) as a single
        string. Empty string if page_start exceeds total page count.

    Raises:
        FileNotFoundError: if the file does not exist.
        ValueError: if page_start < 1 or page_end < page_start.
    """
    return await asyncio.to_thread(_extract_text, path, page_start, page_end)


@mcp.tool()
async def extract_annotations(
    path: str,
    page_start: int | None = None,
    page_end: int | None = None,
) -> list[Annotation]:
    """Extract annotations (highlights, notes, underlines, etc.) from a PDF.

    Uses pdfannots. Page numbers are 1-based. For 'note' annotations the
    text field contains the note body; for marks it contains the highlighted
    text.

    For large PDFs pass ``page_start``/``page_end`` (1-based, inclusive) to
    filter annotations to a page range. Filtering happens after extraction
    (pdfannots doesn't accept range args), so the speedup is on result size,
    not parse time — for very large PDFs prefer ``count_pages`` first.

    Args:
        path: Absolute path to a PDF file.
        page_start: 1-based start page (inclusive). None = from page 1.
        page_end: 1-based end page (inclusive). None = to last page.

    Returns:
        List of Annotation objects (may be empty if the PDF has no marks
        in the requested range).

    Raises:
        FileNotFoundError: if the file does not exist.
        ValueError: if page_start < 1 or page_end < page_start.
    """
    return await asyncio.to_thread(_extract_annotations, path, page_start, page_end)


@mcp.tool()
async def count_pages(path: str) -> int:
    """Return the number of pages in a PDF.

    Cheap pre-flight check before calling extract_text/extract_annotations
    on large PDFs. Use it to decide chunk size (e.g. 50 pages per call).

    Args:
        path: Absolute path to a PDF file.

    Returns:
        Page count as integer.

    Raises:
        FileNotFoundError: if the file does not exist.
    """
    return await asyncio.to_thread(_count_pages, path)
