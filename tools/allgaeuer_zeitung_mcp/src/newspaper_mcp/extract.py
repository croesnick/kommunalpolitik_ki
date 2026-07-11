"""Article extraction: trafilatura + JSON-LD metadata + DOM fallback."""

from __future__ import annotations

import json
import logging

from bs4 import BeautifulSoup

from .models import Article

log = logging.getLogger(__name__)


def is_body_truncated(html: str) -> bool:
    """Check if the article body is truncated (Piano paywall placeholder present).

    Premium articles render only the first paragraph server-side; the rest is
    loaded via JavaScript (Piano). We detect this by checking for the
    ``piano-inline-paywall`` placeholder inside ``#article-body-paid-content``.
    """
    from bs4 import BeautifulSoup

    soup = BeautifulSoup(html, "lxml")
    paid = soup.select_one("#article-body-paid-content")
    if not paid:
        return False
    piano = paid.find(class_="piano-inline-paywall") or paid.find(id="piano-inline-paywall")
    if not piano:
        return False
    # Count substantial paragraphs before the paywall
    paragraphs = []
    for sib in piano.previous_siblings:
        if hasattr(sib, "find_all"):
            paragraphs.extend(sib.find_all("p"))
    substantial = [p for p in paragraphs if len(p.get_text(strip=True)) > 30]
    # If only 0-1 paragraphs before the paywall, body is truncated
    return len(substantial) <= 1


def _extract_jsonld(soup: BeautifulSoup) -> dict | None:
    """Find the NewsArticle JSON-LD block and return it as a dict."""
    for script in soup.find_all("script", type="application/ld+json"):
        try:
            data = json.loads(script.string or "")
        except (json.JSONDecodeError, TypeError):
            continue
        items = data if isinstance(data, list) else [data]
        for item in items:
            if isinstance(item, dict) and item.get("@type") == "NewsArticle":
                return item
    return None


def _extract_body_from_dom(soup: BeautifulSoup) -> str:
    """Fallback: extract text from ``#article-body-paid-content`` or free variant."""
    container = soup.select_one(
        "#article-body-paid-content, #article-body-free-content, "
        '[id*="article-body"], [itemprop="articleBody"]'
    )
    if not container:
        return ""

    paragraphs: list[str] = []
    for el in container.find_all(["p", "h2", "h3", "h4", "li"]):
        text = el.get_text(separator=" ", strip=True)
        if text and len(text) > 10:
            if el.name in {"h2", "h3", "h4"}:
                paragraphs.append(f"\n## {text}\n")
            else:
                paragraphs.append(text)
    return "\n\n".join(paragraphs).strip()


def _extract_kicker(soup: BeautifulSoup) -> str | None:
    # The topline span contains the kicker, but is often followed by the h2 title
    # in the same parent. We only want the topline text itself.
    el = soup.select_one('article span[class*="topline"]')
    if el:
        text = el.get_text(strip=True)
        # The topline span sometimes wraps the headline too; take only the
        # first line / segment before the headline text.
        h2 = soup.select_one("article h2, article h3")
        if h2:
            title = h2.get_text(strip=True)
            if title and text.endswith(title):
                text = text[: -len(title)].strip()
        return text or None
    return None


def _extract_author_from_dom(soup: BeautifulSoup) -> str | None:
    meta = soup.select_one(
        'article [class*="author"], article [class*="Author"], '
        'article [rel="author"]'
    )
    if meta:
        text = meta.get_text(" ", strip=True)
        text = text.replace("Von", "").strip()
        return text or None
    return None


def _extract_image(jsonld: dict | None, soup: BeautifulSoup) -> str | None:
    if jsonld and jsonld.get("image"):
        images = jsonld["image"]
        if isinstance(images, list) and images:
            return images[0].get("url") if isinstance(images[0], dict) else None
        if isinstance(images, dict):
            return images.get("url")
    og_image = soup.select_one('meta[property="og:image"]')
    if og_image:
        content = og_image.get("content")
        return content if isinstance(content, str) else None
    return None


def extract_article(html: str, url: str) -> Article:
    """Extract a clean Article from raw page HTML.

    Uses trafilatura for the body, JSON-LD for metadata, with DOM fallback.
    """
    soup = BeautifulSoup(html, "lxml")
    jsonld = _extract_jsonld(soup)

    import trafilatura

    body_text = trafilatura.extract(
        html,
        output_format="txt",
        include_links=True,
        include_images=False,
        include_tables=True,
        favor_recall=True,
    )
    if not body_text or len(body_text) < 100:
        log.debug("trafilatura returned short/empty body, falling back to DOM")
        body_text = _extract_body_from_dom(soup)

    title = (
        jsonld.get("headline")
        if jsonld
        else None
    ) or _extract_title(soup)

    author = None
    if jsonld and jsonld.get("author"):
        authors = jsonld["author"]
        if isinstance(authors, list):
            author = ", ".join(a.get("name", "") for a in authors if isinstance(a, dict))
        elif isinstance(authors, dict):
            author = authors.get("name")
    if not author:
        author = _extract_author_from_dom(soup)

    date_published = None
    if jsonld:
        date_published = jsonld.get("datePublished") or jsonld.get("dateModified")

    description = None
    if jsonld:
        description = jsonld.get("description")
    if not description:
        og_desc = soup.select_one('meta[property="og:description"]')
        if og_desc:
            content = og_desc.get("content")
            description = content if isinstance(content, str) else None

    is_premium = False
    if jsonld:
        is_premium = not jsonld.get("isAccessibleForFree", True)

    return Article(
        url=url,
        title=title or "(ohne Titel)",
        kicker=_extract_kicker(soup),
        author=author,
        date_published=date_published,
        description=description,
        body_text=body_text or "",
        image_url=_extract_image(jsonld, soup),
        is_premium=is_premium,
    )


def _extract_title(soup: BeautifulSoup) -> str | None:
    h1 = soup.find("h1")
    if h1:
        return h1.get_text(strip=True)
    og = soup.select_one('meta[property="og:title"]')
    if og:
        content = og.get("content")
        return content if isinstance(content, str) else None
    return None
