"""Entry point: run the MCP server via stdio, or a small CLI for shell use.

With no subcommand, runs the MCP server (stdio transport). Subcommands:

    python -m pdf_ingest count <path>
        Print the page count of a PDF.

    python -m pdf_ingest text <path> [--start N] [--end N]
        Print the extracted fulltext of a PDF (or a page range) to stdout.

    python -m pdf_ingest annots <path> [--start N] [--end N]
        Print annotations as a JSON array to stdout.

    python -m pdf_ingest ingest <path> [--start N] [--end N]
        Print a full IngestResult (text + annots + metadata) as JSON to stdout.

``--start`` / ``--end`` are 1-based and inclusive. They make large PDFs
processable in chunks (avoids MCP client timeouts on 50+ MB / 500+ page
documents).
"""

from __future__ import annotations

import argparse
import json
import sys
from collections.abc import Sequence

from .extractor import extract_annotations, extract_text
from .models import IngestResult
from .ocr import count_pages
from .server import _ingest_sync, mcp


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="pdf_ingest",
        description=(
            "PDF ingestion tools. With no subcommand, runs the MCP server "
            "(stdio). Subcommands operate on a single PDF file."
        ),
    )
    sub = parser.add_subparsers(dest="command")

    p_count = sub.add_parser("count", help="Print the page count of a PDF.")
    p_count.add_argument("path", help="Path to a PDF file")

    def _add_range_args(p: argparse.ArgumentParser) -> None:
        p.add_argument(
            "--start",
            type=int,
            default=None,
            help="1-based start page (inclusive). Default: 1.",
        )
        p.add_argument(
            "--end",
            type=int,
            default=None,
            help="1-based end page (inclusive). Default: last page.",
        )

    p_text = sub.add_parser(
        "text", help="Extract fulltext (or a page range) to stdout."
    )
    p_text.add_argument("path", help="Path to a PDF file")
    _add_range_args(p_text)

    p_annots = sub.add_parser(
        "annots",
        help="Extract annotations as a JSON array to stdout.",
    )
    p_annots.add_argument("path", help="Path to a PDF file")
    _add_range_args(p_annots)

    p_ingest = sub.add_parser(
        "ingest",
        help="Run the full pipeline and print an IngestResult JSON to stdout.",
    )
    p_ingest.add_argument("path", help="Path to a PDF file")
    _add_range_args(p_ingest)

    return parser


def main(argv: Sequence[str] | None = None) -> None:
    """CLI entry point. ``argv=None`` means ``sys.argv[1:]``."""
    parser = _build_parser()
    args = parser.parse_args(argv)

    command: str | None = getattr(args, "command", None)
    if command is None:
        # No subcommand → run the MCP server (default behavior).
        mcp.run(transport="stdio")
        return

    if command == "count":
        print(count_pages(args.path))
        return

    if command == "text":
        text = extract_text(args.path, page_start=args.start, page_end=args.end)
        sys.stdout.write(text)
        if not text.endswith("\n") and text:
            sys.stdout.write("\n")
        return

    if command == "annots":
        annots = extract_annotations(
            args.path, page_start=args.start, page_end=args.end
        )
        json.dump(
            [a.model_dump() for a in annots],
            sys.stdout,
            ensure_ascii=False,
            indent=2,
        )
        sys.stdout.write("\n")
        return

    if command == "ingest":
        result: IngestResult = _ingest_sync(
            args.path, page_start=args.start, page_end=args.end
        )
        json.dump(
            result.model_dump(),
            sys.stdout,
            ensure_ascii=False,
            indent=2,
        )
        sys.stdout.write("\n")
        return

    parser.print_help()


if __name__ == "__main__":
    main()
