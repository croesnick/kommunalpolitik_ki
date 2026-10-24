.PHONY: test lint format ci deps elixir-test python-test install komki

# Escript bauen und nach /usr/local/bin symlinken.
# Workspace-Pattern: mix.exs der ratsinfo-App referenziert ../artifacts/deps
# und ../workspace.lock, daher muss der Build aus apps/ratsinfo laufen.
# /usr/local/bin benötigt i.d.R. sudo — ggf. `sudo make install` oder
# stattdessen nach ~/.local/bin symlinken (siehe Hinweis unten).
install:
	cd apps/ratsinfo && mix escript.build
	ln -sf "$(PWD)/apps/ratsinfo/ratsinfo" /usr/local/bin/ratsinfo
	@echo ""
	@echo "ratsinfo installiert: $(PWD)/apps/ratsinfo/ratsinfo -> /usr/local/bin/ratsinfo"
	@echo "Falls der Symlink-Rechte fehlt: sudo make install"
	@echo "Alternative ohne sudo: ln -sf $(PWD)/apps/ratsinfo/ratsinfo ~/.local/bin/ratsinfo"

# komki bauen und in den PATH legen (Tickets #176, #179): ein Programm, das
# Vermittler, Egress-Proxy und Connectoren als Rollen enthaelt.
KOMKI_LINK_DIR ?= $(HOME)/.local/bin
komki:
	@cd apps/komki_cli && mix deps.get >/dev/null && mix escript.build
	@mkdir -p "$(KOMKI_LINK_DIR)"
	@ln -sf "$(PWD)/apps/komki_cli/komki" "$(KOMKI_LINK_DIR)/komki"
	@echo ""
	@echo "komki gebaut: $(KOMKI_LINK_DIR)/komki"
	@echo "Weiter mit: komki setup"

deps:
	mix deps.get
	cd tools/allgaeuer_zeitung_mcp && uv sync
	cd tools/nextcloud_ods_mcp && uv sync

test: elixir-test python-test

elixir-test:
	mix workspace.run -t test --affected

python-test:
	cd tools/allgaeuer_zeitung_mcp && uv run pytest
	cd tools/nextcloud_ods_mcp && uv run pytest

lint:
	mix credo --strict
	mix format --check-formatted
	cd tools/allgaeuer_zeitung_mcp && uv run ruff check
	cd tools/allgaeuer_zeitung_mcp && uv run mypy src/
	cd tools/nextcloud_ods_mcp && uv run ruff check
	cd tools/nextcloud_ods_mcp && uv run mypy src/

format:
	mix format
	cd tools/allgaeuer_zeitung_mcp && uv run ruff format
	cd tools/nextcloud_ods_mcp && uv run ruff format

ci: deps lint test
