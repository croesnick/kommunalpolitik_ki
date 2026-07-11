"""Playwright fallback for JS-rendered (Piano paywall) article content.

Uses a persistent browser profile so the Piano browser ID (__tbc cookie) and
session are preserved between invocations. The Piano JS only loads paid
content if it recognises the browser — this requires the persistent profile.
"""

from __future__ import annotations

import asyncio
import logging
import os
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from playwright.async_api import BrowserContext, Page

log = logging.getLogger(__name__)

_PROFILE_DIR = os.path.expanduser("~/.newspaper_mcp/browser_profile")
_LOCK = asyncio.Lock()
_context: "BrowserContext | None" = None
_logged_in = False


async def _ensure_context() -> "BrowserContext":
    """Return the persistent browser context, creating it if needed."""
    global _context

    if _context is not None:
        try:
            page = await _context.new_page()
            await page.close()
            return _context
        except Exception:
            _context = None

    from playwright.async_api import async_playwright

    os.makedirs(_PROFILE_DIR, exist_ok=True)

    async with _LOCK:
        if _context is not None:
            return _context

        pw = await async_playwright().start()
        _context = await pw.chromium.launch_persistent_context(
            _PROFILE_DIR,
            headless=True,
            args=["--disable-blink-features=AutomationControlled"],
        )
        return _context


async def _ensure_logged_in(page: "Page") -> bool:
    """Ensure the browser session is logged in. Returns True if logged in."""
    global _logged_in

    if _logged_in:
        return True

    from .auth import _load_credentials

    creds = _load_credentials()

    # Check if already logged in (from persistent profile)
    logout = await page.query_selector('a[href*="logout"]')
    if logout:
        _logged_in = True
        return True

    # Perform login via www/sso/login (preserves redirect_uri)
    log.info("Performing Playwright login for persistent browser profile…")
    await page.goto(
        "https://www.allgaeuer-zeitung.de/sso/login",
        wait_until="networkidle",
    )

    # The SSO flow may redirect through anmelden.allgaeuer-zeitung.de.
    # Wait for the login form to appear.
    try:
        await page.wait_for_selector('input[name="username"], input[type="email"]', timeout=10000)
    except Exception:
        # Maybe already logged in (redirected back to www)
        logout = await page.query_selector('a[href*="logout"]')
        if logout:
            _logged_in = True
            return True
        # Navigate to login page directly
        await page.goto("https://anmelden.allgaeuer-zeitung.de/anmelden", wait_until="networkidle")

    await page.fill('input[name="username"], input[type="email"]', creds.email)
    await page.fill('input[name="password"], input[type="password"]', creds.password)
    await page.get_by_role("button", name="Anmelden").click()

    try:
        await page.wait_for_url("**www.allgaeuer-zeitung.de/**", timeout=30000)
    except Exception:
        # Might redirect to service.allgaeuer-zeitung.de first
        await page.wait_for_timeout(5000)
        await page.goto("https://www.allgaeuer-zeitung.de/", wait_until="networkidle")

    await page.wait_for_load_state("networkidle")
    await page.wait_for_timeout(2000)

    # Accept consent dialog
    try:
        await page.get_by_role("button", name="Akzeptieren und weiter").click(timeout=5000)
        await page.wait_for_load_state("networkidle")
    except Exception:
        pass

    # Reload to let Piano JS pick up the session
    await page.reload(wait_until="networkidle")
    await page.wait_for_timeout(3000)

    # Verify login
    logout = await page.query_selector('a[href*="logout"]')
    if logout:
        _logged_in = True
        log.info("Playwright persistent session logged in")
        return True

    # Check Piano state
    state = await page.evaluate(
        """() => window.tp?.customVariables?.userLoginState || 'unknown'"""
    )
    log.warning("Login state unclear. Piano userLoginState=%s", state)
    return state == "true"


async def get_cookies_from_browser() -> list[dict]:
    """Log in via the persistent browser and return all cookies.

    Used by ``auth.ensure_cookies()`` to cache cookies for HTTP-only requests.
    """
    context = await _ensure_context()
    page = await context.new_page()
    try:
        await _ensure_logged_in(page)
        return [dict(c) for c in await context.cookies()]
    finally:
        await page.close()


async def fetch_article_with_playwright(url: str) -> str:
    """Fetch an article using the persistent logged-in browser.

    Piano JS runs in this context and injects the paid content into the DOM.
    The persistent profile preserves the Piano browser session between calls.
    """
    context = await _ensure_context()
    page = await context.new_page()
    try:
        await _ensure_logged_in(page)

        await page.goto(url, wait_until="networkidle")

        # Dismiss consent dialog if it appears
        try:
            await page.get_by_role("button", name="Akzeptieren und weiter").click(timeout=3000)
            await page.wait_for_load_state("networkidle")
        except Exception:
            pass

        # Wait for Piano to inject the paid content (second <p> appears)
        try:
            await page.wait_for_selector(
                "#article-body-paid-content p:nth-of-type(2)", timeout=15000
            )
        except Exception:
            log.warning("Piano did not inject paid content for %s", url)

        await page.wait_for_timeout(500)

        return await page.content()
    finally:
        await page.close()
