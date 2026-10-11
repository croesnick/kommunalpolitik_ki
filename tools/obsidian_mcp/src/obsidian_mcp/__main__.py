"""Einstiegspunkt für `python -m obsidian_mcp`."""

from obsidian_mcp.server import mcp


def main() -> None:
    """Startet den FastMCP-Server auf stdio."""
    mcp.run()


if __name__ == "__main__":
    main()
