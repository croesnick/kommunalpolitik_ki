"""MCP server exposing Allgäuer Zeitung tools."""

from __future__ import annotations

import logging

from mcp.server.fastmcp import FastMCP

from .client import fetch_article_html, fetch_html
from .extract import extract_article
from .models import Article, SearchResult, Section
from .parsers import parse_article_list, parse_search_url, parse_section_url

log = logging.getLogger(__name__)

mcp = FastMCP(
    "newspaper-mcp",
    instructions=(
        "MCP server for the Allgäuer Zeitung newspaper (allgaeuer-zeitung.de). "
        "Tools: search_articles, get_article, list_latest, list_sections. "
        "All article text is returned clean (no ads/navigation). "
        "Authentication is handled automatically via cached session cookies."
    ),
)

SECTIONS: list[Section] = [
    Section(name="Startseite", slug="home", url="https://www.allgaeuer-zeitung.de/"),
    Section(
        name="Allgäu", slug="allgaeu", url="https://www.allgaeuer-zeitung.de/allgaeu"
    ),
    Section(
        name="Kempten", slug="kempten", url="https://www.allgaeuer-zeitung.de/kempten"
    ),
    Section(
        name="Oberallgäu",
        slug="immenstadt",
        url="https://www.allgaeuer-zeitung.de/immenstadt",
    ),
    Section(
        name="Memmingen",
        slug="memmingen",
        url="https://www.allgaeuer-zeitung.de/memmingen",
    ),
    Section(
        name="Kaufbeuren",
        slug="kaufbeuren",
        url="https://www.allgaeuer-zeitung.de/kaufbeuren",
    ),
    Section(
        name="Füssen", slug="fuessen", url="https://www.allgaeuer-zeitung.de/fuessen"
    ),
    Section(
        name="Westallgäu", slug="weiler", url="https://www.allgaeuer-zeitung.de/weiler"
    ),
    Section(
        name="Marktoberdorf",
        slug="marktoberdorf",
        url="https://www.allgaeuer-zeitung.de/marktoberdorf",
    ),
    Section(
        name="Buchloe", slug="buchloe", url="https://www.allgaeuer-zeitung.de/buchloe"
    ),
    Section(
        name="Bilder", slug="bilder", url="https://www.allgaeuer-zeitung.de/bilder"
    ),
    Section(name="Sport", slug="sport", url="https://www.allgaeuer-zeitung.de/sport"),
    Section(
        name="AZ+",
        slug="azplus",
        url="https://www.allgaeuer-zeitung.de/specials/azplus",
    ),
]


@mcp.tool()
async def search_articles(query: str, limit: int = 10) -> list[SearchResult]:
    """Search the Allgäuer Zeitung for articles by keyword.

    Args:
        query: Search term (e.g. "Nebelhorn", "Kempten Rathaus").
        limit: Max results to return (default 10, max 30).

    Returns:
        List of matching articles with title, URL, date, author, and premium flag.
    """
    limit = max(1, min(limit, 30))
    url = parse_search_url(query)
    html = await fetch_html(url)
    return parse_article_list(html, limit=limit)


@mcp.tool()
async def get_article(url: str) -> Article:
    """Fetch and extract a single article by its URL.

    Returns the full article body text without ads, navigation, or related articles.
    Metadata (title, author, date, image) is parsed from JSON-LD structured data.

    Args:
        url: Full article URL (e.g. https://www.allgaeuer-zeitung.de/allgaeu/...).

    Returns:
        Article object with title, author, date_published, body_text, and more.
    """
    html = await fetch_article_html(url)
    return extract_article(html, url)


@mcp.tool()
async def list_latest(section: str = "allgaeu", limit: int = 20) -> list[SearchResult]:
    """List the latest articles from a newspaper section.

    Args:
        section: Section slug (e.g. "allgaeu", "kempten", "sport", "home" for homepage).
                 Use list_sections to see all available sections.
        limit: Max results to return (default 20, max 50).

    Returns:
        List of articles with title, URL, date, author, and premium flag.
    """
    limit = max(1, min(limit, 50))
    url = parse_section_url(section)
    html = await fetch_html(url)
    return parse_article_list(html, limit=limit)


@mcp.tool()
async def list_sections() -> list[Section]:
    """List all available newspaper sections (e.g. Allgäu, Kempten, Sport).

    Use the ``slug`` value as the ``section`` argument to ``list_latest``.

    Returns:
        List of sections with name, slug, and URL.
    """
    return SECTIONS
