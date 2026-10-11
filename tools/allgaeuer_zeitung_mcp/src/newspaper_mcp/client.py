"""HTTP client with automatic cookie injection and re-login on auth failure."""

from __future__ import annotations

import asyncio
import logging

import httpx

from .auth import ensure_cookies

log = logging.getLogger(__name__)

BASE_URL = "https://www.allgaeuer-zeitung.de"
LOGIN_REDIRECT_FRAGMENT = "/sso/login"
PAYWALL_MARKER = "pgwl_purGatewayLayer"

_cookie_cache: list[dict] | None = None
_cookie_lock = asyncio.Lock()


async def _get_cookies() -> list[dict]:
    global _cookie_cache
    if _cookie_cache is not None:
        return _cookie_cache
    _cookie_cache = await ensure_cookies()
    return _cookie_cache


def _build_client(cookies: list[dict]) -> httpx.AsyncClient:
    jar = httpx.Cookies()
    for c in cookies:
        jar.set(
            c["name"], c["value"], domain=c.get("domain", ""), path=c.get("path", "/")
        )
    return httpx.AsyncClient(
        cookies=jar,
        headers={
            "User-Agent": (
                "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
                "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36"
            ),
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            "Accept-Language": "de-DE,de;q=0.9,en;q=0.8",
        },
        follow_redirects=True,
        timeout=30.0,
    )


async def _is_auth_failure(response: httpx.Response) -> bool:
    if response.status_code == 401 or response.status_code == 403:
        return True
    if LOGIN_REDIRECT_FRAGMENT in str(response.url):
        return True
    text = response.text
    if "Bitte anmelden" in text and "anmelden.allgaeuer-zeitung.de" in text:
        return True
    return False


async def fetch_html(url: str, *, force_relogin: bool = False) -> str:
    """Fetch a page with auth cookies, re-login once if the session expired.

    Raises ``httpx.HTTPStatusError`` for non-auth-related failures.
    """
    global _cookie_cache

    if force_relogin:
        _cookie_cache = None

    cookies = await _get_cookies()

    async with _cookie_lock:
        client = _build_client(cookies)
        try:
            response = await client.get(url)
            response.raise_for_status()

            if await _is_auth_failure(response):
                log.info("Auth failure on %s, re-logging in…", url)
                _cookie_cache = None
                cookies = await _get_cookies()
                response = await client.get(url)
                response.raise_for_status()

                if await _is_auth_failure(response):
                    raise RuntimeError(
                        f"Authentication still failing after re-login for {url}"
                    )

            return response.text
        finally:
            await client.aclose()


async def fetch_article_html(url: str) -> str:
    """Fetch an article page, falling back to Playwright for JS-rendered content.

    First tries a fast HTTP request. If the article body is behind a Piano
    paywall (only the first paragraph is present), re-fetches with Playwright
    which executes the JS to load the full subscriber content.
    """
    from .extract import is_body_truncated

    html = await fetch_html(url)

    if is_body_truncated(html):
        log.info(
            "Article body truncated (Piano paywall), falling back to Playwright: %s",
            url,
        )
        from .browser_fallback import fetch_article_with_playwright

        html = await fetch_article_with_playwright(url)

    return html
