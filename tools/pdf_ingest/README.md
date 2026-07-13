# pdf-ingest

MCP server for PDF ingestion: text and annotation extraction with optional OCR.

Orthogonal (Unix-Prinzip): knows nothing about the RIS, ratsprojekte, or any
other tool. Takes a file path, returns extracted data.

## Tools

| Tool | Description |
|------|-------------|
| `ingest(path)` | Full pipeline: text + annotations + OCR if scanned |
| `extract_text(path)` | Fast text-only extraction (no OCR, no annotations) |
| `extract_annotations(path)` | Annotations only (highlights, notes, underlines, etc.) |

## Library stack

| Aufgabe | Library | Lizenz |
|---------|---------|--------|
| Textextraktion | pdfplumber | MIT |
| Annotations/Highlights | pdfannots (baut auf pdfminer.six) | MIT |
| OCR | OCRmyPDF (CLI/Subprocess, nur wenn gescannt) | MPL-2.0 |
| MCP-Framework | FastMCP (mcp) | MIT |

Kein PyMuPDF (AGPL — vermieden).

## Setup

```bash
# Install Python dependencies
uv sync
```

### System requirements (OCR only)

OCR is only invoked when a PDF appears scanned (less than ~50 characters per
page of embedded text). For that you need:

- **OCRmyPDF** — install via `brew install ocrmypdf` (macOS) or
  `apt install ocrmypdf` (Debian/Ubuntu).
- **Tesseract** language packs for German + English (`tesseract-ocr-deu`).

If OCRmyPDF is not installed, `ingest` raises a clear error when a scanned
PDF is encountered. Text-based PDFs work without it.

## Configure in opencode

Add to your `opencode.json`:

```json
{
  "mcp": {
    "pdf-ingest": {
      "type": "local",
      "command": ["uv", "run", "--directory", "tools/pdf_ingest", "pdf-ingest"]
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

MIT (wie das ganze Repo).
