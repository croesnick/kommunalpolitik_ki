"""Pydantic models for MCP tool outputs."""

from __future__ import annotations

from pydantic import BaseModel, Field


class CellMatch(BaseModel):
    """A single search hit within a sheet."""

    row: int = Field(..., description="1-based row number of the match")
    col: int = Field(..., description="1-based column number of the match")
    value: str = Field(..., description="Cell value containing the query")
    cell: str = Field(..., description="A1-style cell reference, e.g. 'B7'")
