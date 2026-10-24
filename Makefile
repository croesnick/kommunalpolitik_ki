.PHONY: test lint format ci deps elixir-test python-test install komki komki-paket komki-formel

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

# Paket fuer die Homebrew-Formel (Ticket #180): das Escript (prod) und die
# SQLite-NIF von exqlite nebeneinander, als dist/komki-<version>-macos-arm64.tar.gz.
KOMKI_VERSION = $(shell grep -m1 'version:' apps/komki_cli/mix.exs | sed 's/.*"\(.*\)".*/\1/')
KOMKI_PAKET = dist/komki-$(KOMKI_VERSION)-macos-arm64
komki-paket:
	@cd apps/komki_cli && MIX_ENV=prod mix deps.get >/dev/null && MIX_ENV=prod mix escript.build
	@rm -rf "$(KOMKI_PAKET)" && mkdir -p "$(KOMKI_PAKET)/lib/exqlite"
	@cp apps/komki_cli/komki "$(KOMKI_PAKET)/komki"
	@cp -R apps/komki_cli/_build/prod/lib/exqlite/ebin apps/komki_cli/_build/prod/lib/exqlite/priv "$(KOMKI_PAKET)/lib/exqlite/"
	@tar -C dist -czf "$(KOMKI_PAKET).tar.gz" "$(notdir $(KOMKI_PAKET))"
	@shasum -a 256 "$(KOMKI_PAKET).tar.gz"

# Formel fuer das Tap-Repo aus der Vorlage: Version und Pruefsumme des Pakets.
komki-formel: komki-paket
	@sha=$$(shasum -a 256 "$(KOMKI_PAKET).tar.gz" | cut -d' ' -f1); \
	  sed -e "s/@VERSION@/$(KOMKI_VERSION)/g" -e "s/@SHA256@/$$sha/" packaging/homebrew/komki.rb.in > dist/komki.rb
	@echo "Formel geschrieben: dist/komki.rb (ins Tap-Repo croesnick/homebrew-komki als Formula/komki.rb)"

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
