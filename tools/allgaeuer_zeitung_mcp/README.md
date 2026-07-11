# newspaper-mcp

MCP server for the [Allgäuer Zeitung](https://www.allgaeuer-zeitung.de/) online newspaper.

Exposes four tools for searching and reading articles — clean text, no ads or
navigation. Handles authentication (including the Piano paywall) automatically.

## Tools

| Tool | Description |
|------|-------------|
| `search_articles(query, limit)` | Search articles by keyword |
| `get_article(url)` | Fetch a single article with full body text (no ads) |
| `list_latest(section, limit)` | List latest articles from a section |
| `list_sections()` | List all available newspaper sections |

## How it works

- **Search & listing**: Fast HTTP requests with cached auth cookies
- **Article body**: trafilatura extraction from raw HTML
- **Premium articles (AZ+)**: Falls back to a persistent headless browser
  (Playwright) that handles the Piano paywall JS. The browser profile is
  reused between calls, so subsequent fetches are fast.

## Setup

```bash
# Install dependencies
uv sync

# Install Playwright browser (one-time)
uv run playwright install chromium

# Store credentials in OS keyring (recommended)
uv run python -m newspaper_mcp.auth
# Or set env vars:
export AZ_EMAIL="your@email.de"
export AZ_PASSWORD="your-password"
```

## Configure in opencode

Add to your `opencode.json`:

```json
{
  "mcp": {
    "newspaper-mcp": {
      "type": "local",
      "command": ["uv", "run", "--directory", "/Users/crn/projects/newspaper_mcp", "python", "-m", "newspaper_mcp"],
      "environment": {
        "AZ_EMAIL": "your@email.de",
        "AZ_PASSWORD": "your-password"
      }
    }
  }
}
```

## Development

```bash
uv sync                          # install deps
uv run playwright install chromium  # install browser
uv run pytest                     # run tests
```
