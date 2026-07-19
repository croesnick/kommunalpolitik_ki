"""Text and annotation extraction from PDFs.

Text extraction uses :mod:`pdfplumber` (MIT). Annotation extraction uses
:mod:`pdfannots` (MIT), which builds on ``pdfminer.six``.

This module is orthogonal (Unix-Prinzip): it knows nothing about the RIS,
ratsprojekte, or any other tool. It takes a file path and returns data.
"""

from __future__ import annotations

from pathlib import Path
from typing import Any

import pdfplumber
from pdfannots import process_file
from pdfannots.types import AnnotationType

from .models import Annotation

#: Maps pdfannots AnnotationType enum names to our normalized type strings.
_SUBTYPE_MAP: dict[str, str] = {
    "Highlight": "highlight",
    "Underline": "underline",
    "StrikeOut": "strikethrough",
    "Squiggly": "squiggly",
    "Text": "note",
}


def _map_subtype(subtype: AnnotationType) -> str:
    """Map a pdfannots AnnotationType to our normalized type string.

    Unknown subtypes fall back to the lowercased enum name.
    """
    name = subtype.name
    return _SUBTYPE_MAP.get(name, name.lower())


def _hex_color(color: Any) -> str | None:
    """Convert a pdfannots RGB color to a ``#rrggbb`` hex string."""
    if color is None:
        return None
    ashex = getattr(color, "ashex", None)
    if ashex is None:
        return None
    return "#" + str(ashex())


def _annot_text(annot: Any) -> str:
    """Extract display text from a pdfannots Annotation.

    For marks (highlight/underline/...) uses ``gettext()``; for notes (Text
    annotations) falls back to ``contents`` (the comment body).
    """
    text: Any = None
    gettext = getattr(annot, "gettext", None)
    if callable(gettext):
        try:
            text = gettext(remove_hyphens=False)
        except Exception:
            text = None
    if not text:
        text = getattr(annot, "contents", None)
    return str(text) if text else ""


def _created_iso(annot: Any) -> str | None:
    """Return the annotation creation timestamp as ISO-8601, or None."""
    created = getattr(annot, "created", None)
    if created is None:
        return None
    strftime = getattr(created, "strftime", None)
    if callable(strftime):
        try:
            return str(strftime("%Y-%m-%dT%H:%M:%S"))
        except Exception:
            return str(created)
    return str(created)


def _validate_page_range(page_start: int | None, page_end: int | None) -> None:
    """Validate 1-based inclusive page range parameters.

    Args:
        page_start: 1-based start page (inclusive). None = from page 1.
        page_end: 1-based end page (inclusive). None = to last page.

    Raises:
        ValueError: if page_start < 1 or page_end < page_start.
    """
    if page_start is not None and page_start < 1:
        raise ValueError("page_start must be 1-based (>= 1)")
    if page_end is not None and page_start is not None and page_end < page_start:
        raise ValueError("page_end must be >= page_start")


def _resolve_range(
    total_pages: int,
    page_start: int | None,
    page_end: int | None,
) -> tuple[int, int]:
    """Resolve a 1-based inclusive [start, end] range against a page count.

    Clamps page_end to total_pages. If page_start exceeds total_pages,
    returns an empty range (start > end) so callers can produce an empty
    result without erroring.
    """
    start = page_start if page_start is not None else 1
    end = page_end if page_end is not None else total_pages
    if start > total_pages:
        # Empty range — caller should return empty result.
        return start, start - 1
    if end > total_pages:
        end = total_pages
    return start, end


def extract_text(
    path: str,
    page_start: int | None = None,
    page_end: int | None = None,
) -> str:
    """Extract fulltext from a PDF via pdfplumber.

    Pages are joined with a blank line separator. When ``page_start`` and
    ``page_end`` are given (1-based, inclusive), only that page range is
    extracted — useful for large PDFs that would otherwise time out. Does
    not run OCR and does not extract annotations — use :func:`ingest` for
    the full pipeline.

    Args:
        path: Path to a PDF file.
        page_start: 1-based start page (inclusive). None = from page 1.
        page_end: 1-based end page (inclusive). None = to last page.

    Raises:
        FileNotFoundError: if the file does not exist.
        ValueError: if page_start < 1 or page_end < page_start.
        pdfplumber.pdfplumber.PDFSyntaxError: if the file is not a valid PDF.
    """
    if not Path(path).is_file():
        raise FileNotFoundError(f"PDF not found: {path}")

    _validate_page_range(page_start, page_end)

    pages: list[str] = []
    with pdfplumber.open(path) as pdf:
        total_pages = len(pdf.pages)
        start, end = _resolve_range(total_pages, page_start, page_end)
        if start > end:
            return ""
        # 1-based inclusive → 0-based slice end is `end` (i.e. end-1+1 = end)
        for page in pdf.pages[start - 1 : end]:
            text = page.extract_text() or ""
            pages.append(text)
    return "\n\n".join(pages)


def extract_annotations(
    path: str,
    page_start: int | None = None,
    page_end: int | None = None,
) -> list[Annotation]:
    """Extract annotations (highlights, notes, etc.) from a PDF.

    Uses pdfannots to parse the PDF and resolve mark text. Page numbers are
    1-based. When ``page_start`` and ``page_end`` are given (1-based,
    inclusive), only annotations on pages within that range are returned —
    pdfannots doesn't accept range args, so filtering happens after
    extraction (the cost is reading annotation metadata, not re-parsing).

    Args:
        path: Path to a PDF file.
        page_start: 1-based start page (inclusive). None = from page 1.
        page_end: 1-based end page (inclusive). None = to last page.

    Raises:
        FileNotFoundError: if the file does not exist.
        ValueError: if page_start < 1 or page_end < page_start.
    """
    if not Path(path).is_file():
        raise FileNotFoundError(f"PDF not found: {path}")

    _validate_page_range(page_start, page_end)

    annotations: list[Annotation] = []
    with open(path, "rb") as fh:
        doc = process_file(fh)

    for annot in doc.iter_annots():
        pos = getattr(annot, "pos", None)
        page_num = getattr(pos, "page", None)
        pageno = getattr(page_num, "pageno", None) if page_num is not None else None
        if pageno is None:
            # Skip annotations without positional info (shouldn't normally happen).
            continue
        page_1based = pageno + 1  # 1-based
        if page_start is not None and page_1based < page_start:
            continue
        if page_end is not None and page_1based > page_end:
            continue
        annotations.append(
            Annotation(
                page=page_1based,
                type=_map_subtype(annot.subtype),
                text=_annot_text(annot),
                color=_hex_color(getattr(annot, "color", None)),
                author=getattr(annot, "author", None),
                created=_created_iso(annot),
            )
        )
    return annotations
