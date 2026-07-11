"""Pydantic models for MCP tool outputs."""

from __future__ import annotations

from pydantic import BaseModel, Field


class SearchResult(BaseModel):
    """A single article reference returned by search or list_latest."""

    article_id: str = Field(..., description="Unique numeric article ID from the site")
    title: str
    url: str
    kicker: str | None = Field(None, description="Category/label shown above the title")
    date: str | None = Field(None, description="Publication date as displayed on the page")
    author: str | None = None
    is_premium: bool = Field(False, description="Whether the article is behind the AZ+ paywall")


class Article(BaseModel):
    """Full article content extracted from a single page."""

    url: str
    title: str
    kicker: str | None = None
    author: str | None = None
    date_published: str | None = Field(None, description="ISO 8601 publication timestamp")
    description: str | None = Field(None, description="Article teaser/lead paragraph")
    body_text: str = Field(..., description="Clean article body text, no ads or navigation")
    image_url: str | None = None
    is_premium: bool = False


class Section(BaseModel):
    """A newspaper section (e.g. Allgäu, Kempten, Sport)."""

    name: str
    slug: str = Field(..., description="URL path segment, e.g. 'allgaeu'")
    url: str
