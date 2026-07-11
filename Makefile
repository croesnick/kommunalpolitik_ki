.PHONY: test lint format ci deps elixir-test python-test

deps:
	mix deps.get
	cd tools/allgaeuer_zeitung_mcp && uv sync

test: elixir-test python-test

elixir-test:
	mix workspace.run -t test --affected

python-test:
	cd tools/allgaeuer_zeitung_mcp && uv run pytest

lint:
	mix credo --strict
	mix format --check-formatted
	cd tools/allgaeuer_zeitung_mcp && uv run ruff check
	cd tools/allgaeuer_zeitung_mcp && uv run mypy src/

format:
	mix format
	cd tools/allgaeuer_zeitung_mcp && uv run ruff format

ci: deps lint test
