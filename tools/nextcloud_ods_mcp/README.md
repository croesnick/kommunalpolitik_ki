# nextcloud-ods-mcp

MCP server for reading ODS (OpenDocument Spreadsheet) files: list sheets,
read ranges/cells, substring search.

Orthogonal (Unix-Prinzip): knows nothing about Nextcloud, the RIS, or any
other tool. Takes a local file path, returns structured data. The actual
Nextcloud download is the responsibility of a Nextcloud MCP server — this
tool is only the parser.

## Tools

| Tool | Description |
|------|-------------|
| `list_sheets(path)` | List sheet names of an ODS file |
| `read_sheet(path, sheet_name, range?)` | Full sheet (or A1 range like `A1:C10`) as 2D list |
| `read_cell(path, sheet_name, cell)` | Read a single A1 cell (e.g. `B7`) |
| `search_sheet(path, sheet_name, query)` | Case-insensitive substring search across all cells |

Cell values are returned as strings (odfpy provides string representations);
empty cells are `None`.

## Library stack

| Aufgabe | Library | Lizenz |
|---------|---------|--------|
| ODS-Parsing | odfpy | Apache-2.0 |
| MCP-Framework | FastMCP (mcp) | MIT |

## Setup

```bash
# Install Python dependencies
uv sync
```

## Configure in opencode

Add to your `opencode.json`:

```json
{
  "mcp": {
    "nextcloud-ods-mcp": {
      "type": "local",
      "command": ["uv", "run", "--directory", "tools/nextcloud_ods_mcp", "nextcloud-ods-mcp"]
    }
  }
}
```

## Development

```bash
uv sync                       # install deps
uv run ruff check             # lint
uv run ruff format --check    # format check
uv run mypy src/              # type check
uv run pytest                 # tests
```

## License

MIT (wie das ganze Repo). Die Abhängigkeit `odfpy` steht unter Apache-2.0.
