"""Pydantic models for MCP tool outputs."""

from __future__ import annotations

from pydantic import BaseModel, Field


class Annotation(BaseModel):
    """A single PDF annotation (highlight, note, etc.)."""

    page: int = Field(..., description="1-based page number")
    type: str = Field(
        ...,
        description=(
            "Annotation type: 'highlight', 'underline', 'strikethrough', "
            "'note', or 'squiggly'"
        ),
    )
    text: str = Field(
        ..., description="Highlighted text (for marks) or note contents (for notes)"
    )
    color: str | None = Field(
        None, description="Hex color like '#ffff00', or None if not set"
    )
    author: str | None = Field(None, description="Annotation author, if available")
    created: str | None = Field(
        None, description="ISO-8601 creation timestamp, if available"
    )


class IngestResult(BaseModel):
    """Full result of ingesting a PDF: text, annotations, and OCR flag."""

    path: str
    pages: int = Field(..., description="Number of pages in the extracted range")
    pages_total: int = Field(
        ...,
        description="Total pages in the PDF (independent of range)",
    )
    page_start: int | None = Field(
        None,
        description="1-based start page if a range was requested, else None",
    )
    page_end: int | None = Field(
        None,
        description="1-based end page if a range was requested, else None",
    )
    text: str = Field(
        ..., description="Fulltext of the requested page range (may be long)"
    )
    annotations: list[Annotation]
    ocr_used: bool = Field(
        False, description="True if OCR was performed on the document"
    )
