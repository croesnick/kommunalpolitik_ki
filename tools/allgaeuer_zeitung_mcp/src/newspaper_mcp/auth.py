"""Authentication and cookie management for the Allgäuer Zeitung.

Cookies are obtained from the persistent Playwright browser profile (which
handles the Piano SSO handshake) and cached in the OS keyring for fast
HTTP-only requests to search/section pages.
"""

from __future__ import annotations

import json
import os
import time
from dataclasses import dataclass

import keyring
from dotenv import load_dotenv

load_dotenv()

KEYRING_SERVICE = "newspaper_mcp"
COOKIE_KEY = "az_cookies"
CREDS_KEY = "az_credentials"

LOGIN_URL = "https://anmelden.allgaeuer-zeitung.de/anmelden"
HOMEPAGE_URL = "https://www.allgaeuer-zeitung.de/"
COOKIE_MAX_AGE = 5 * 24 * 3600  # 5 days


@dataclass
class Credentials:
    email: str
    password: str


def _load_credentials() -> Credentials:
    """Load credentials from keyring, falling back to env vars."""
    stored = keyring.get_password(KEYRING_SERVICE, CREDS_KEY)
    if stored:
        try:
            data = json.loads(stored)
            return Credentials(email=data["email"], password=data["password"])
        except (json.JSONDecodeError, KeyError):
            pass

    email = os.environ.get("AZ_EMAIL", "")
    password = os.environ.get("AZ_PASSWORD", "")
    if not email or not password:
        raise RuntimeError(
            "AZ_EMAIL and AZ_PASSWORD must be set (env var or keyring). "
            "Run: python -m newspaper_mcp.store_creds"
        )
    return Credentials(email=email, password=password)


@dataclass
class CookieJar:
    """Serialisable cookie list with a creation timestamp."""

    cookies: list[dict]
    created_at: float

    def is_expired(self) -> bool:
        return time.time() - self.created_at > COOKIE_MAX_AGE


def load_cached_cookies() -> CookieJar | None:
    """Load cookies from the OS keyring, or None if missing/expired."""
    raw = keyring.get_password(KEYRING_SERVICE, COOKIE_KEY)
    if not raw:
        return None
    try:
        data = json.loads(raw)
        jar = CookieJar(cookies=data["cookies"], created_at=data["created_at"])
        if jar.is_expired():
            return None
        return jar
    except (json.JSONDecodeError, KeyError):
        return None


def save_cookies(cookies: list[dict]) -> None:
    """Persist cookies to the OS keyring."""
    jar = CookieJar(cookies=cookies, created_at=time.time())
    keyring.set_password(KEYRING_SERVICE, COOKIE_KEY, json.dumps(jar.__dict__))


def clear_cookies() -> None:
    """Remove cached cookies (forces re-login on next call)."""
    try:
        keyring.delete_password(KEYRING_SERVICE, COOKIE_KEY)
    except keyring.errors.PasswordDeleteError:
        pass


async def ensure_cookies() -> list[dict]:
    """Return valid cookies, using the persistent Playwright browser to log in.

    The browser handles the Piano SSO handshake. After login, all cookies
    (including the Piano browser token) are exported and cached in keyring
    for fast HTTP-only requests.
    """
    jar = load_cached_cookies()
    if jar is not None:
        return jar.cookies

    # Use the persistent browser to log in and capture cookies
    from .browser_fallback import get_cookies_from_browser

    cookies = await get_cookies_from_browser()
    save_cookies(cookies)
    return cookies


def _interactive_store_creds() -> None:
    """CLI helper: interactively store credentials in the OS keyring."""
    import getpass

    email = input("Email: ").strip()
    password = getpass.getpass("Password: ")
    keyring.set_password(
        KEYRING_SERVICE,
        CREDS_KEY,
        json.dumps({"email": email, "password": password}),
    )
    print(f"Credentials stored in keyring under service='{KEYRING_SERVICE}'.")


if __name__ == "__main__":
    _interactive_store_creds()
