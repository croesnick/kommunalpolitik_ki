"""BeautifulSoup parsers for search results and section/article-listing pages."""

from __future__ import annotations

from urllib.parse import urljoin

from bs4 import BeautifulSoup, Tag

from .models import SearchResult

BASE_URL = "https://www.allgaeuer-zeitung.de"


def _str_attr(tag: Tag, name: str, default: str = "") -> str:
    """Safely extract a string attribute from a BeautifulSoup Tag."""
    val = tag.get(name, default)
    if isinstance(val, list):
        return val[0] if val else default
    return val if val is not None else default


def _parse_article_teaser(article: Tag) -> SearchResult | None:
    """Parse a single ``<article data-article-id>`` teaser element."""
    article_id = _str_attr(article, "data-article-id")
    if not article_id:
        return None

    link = article.find("a", href=True)
    if not link:
        return None
    href = _str_attr(link, "href")
    url = href if href.startswith("http") else urljoin(BASE_URL, href)

    heading = article.find(["h2", "h3", "h4"])
    title = (
        heading.get_text(strip=True) if heading else (link.get_text(strip=True) or "")
    )

    kicker_el = article.select_one(
        '[class*="topline"], [class*="kicker"], [class*="label"]'
    )
    kicker = kicker_el.get_text(strip=True) if kicker_el else None

    time_el = article.find("time")
    date: str | None = None
    if time_el:
        date = _str_attr(time_el, "datetime") or time_el.get_text(strip=True) or None

    author_el = article.select_one('[class*="author"], [class*="Author"]')
    author = author_el.get_text(strip=True) if author_el else None

    aria_label = _str_attr(article, "aria-label")
    is_premium = "plus" in aria_label.lower() or bool(
        article.select_one('[class*="plus"], [class*="Plus"], [class*="premium"]')
    )

    return SearchResult(
        article_id=article_id,
        title=title or aria_label or "(ohne Titel)",
        url=url,
        kicker=kicker,
        date=date,
        author=author,
        is_premium=is_premium,
    )


def parse_article_list(html: str, limit: int = 20) -> list[SearchResult]:
    """Parse a page containing ``<article data-article-id>`` teasers.

    Used for both search results (``/suche?q=``) and section pages (``/allgaeu`` etc.).
    """
    soup = BeautifulSoup(html, "lxml")
    results: list[SearchResult] = []
    seen_ids: set[str] = set()

    for article in soup.find_all("article", attrs={"data-article-id": True}):
        parsed = _parse_article_teaser(article)
        if parsed and parsed.article_id not in seen_ids:
            results.append(parsed)
            seen_ids.add(parsed.article_id)
        if len(results) >= limit:
            break

    return results


def parse_search_url(query: str) -> str:
    """Build the search URL for a given query."""
    return f"{BASE_URL}/suche?q={httpx_quote(query)}"


def httpx_quote(s: str) -> str:
    from urllib.parse import quote

    return quote(s)


def parse_section_url(slug: str) -> str:
    """Build the section URL. 'home' or '' returns the homepage."""
    if not slug or slug == "home":
        return BASE_URL + "/"
    return f"{BASE_URL}/{slug.lstrip('/')}"
