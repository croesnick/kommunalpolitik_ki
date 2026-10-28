.PHONY: test lint format ci deps elixir-test python-test install komki komki-tresor komki-paket komki-formel komki-tap komki-burrito docs docs-build docs-preview

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
komki: komki-tresor
	@cd apps/komki_cli && mix deps.get >/dev/null && mix escript.build
	@mkdir -p "$(KOMKI_LINK_DIR)"
	@ln -sf "$(PWD)/apps/komki_cli/komki" "$(KOMKI_LINK_DIR)/komki"
	@echo ""
	@echo "komki gebaut: $(KOMKI_LINK_DIR)/komki"
	@echo "Weiter mit: komki setup"

# komki-tresor: versiegelt Geheimnisse mit der Secure Enclave (Swift, weil
# Erlang die Enclave nicht erreicht; Quelle apps/komki_cli/native). komki
# sucht es neben sich selbst. `mix compile` baut es nach apps/komki_cli/priv
# (Ticket #224, braucht swiftc aus den Xcode Command Line Tools); hier nur
# noch neben das Escript kopieren, damit es in allen Kanälen neben komki
# liegt. Der Test bewahrt den lauteren Fehler, wenn swiftc fehlt.
komki-tresor:
	@cd apps/komki_cli && mix deps.get >/dev/null && mix compile
	@cp apps/komki_cli/priv/komki-tresor apps/komki_cli/komki-tresor
	@test -f apps/komki_cli/komki-tresor

# Paket fuer die Homebrew-Formel (Ticket #180): das Escript (prod), die
# SQLite-NIF von exqlite und pi mit allen Abhaengigkeiten nebeneinander, als
# dist/komki-<version>-macos-arm64.tar.gz. pi installiert pnpm nach der
# Lockfile in packaging/pi, ohne Installationsskripte; die Formel kopiert nur
# noch und laedt nichts nach. Vorgebaute Module fuer andere Plattformen und
# die .bin-Links fallen weg.
KOMKI_VERSION = $(shell grep -m1 'version:' apps/komki_cli/mix.exs | sed 's/.*"\(.*\)".*/\1/')
KOMKI_PAKET = dist/komki-$(KOMKI_VERSION)-macos-arm64
komki-paket: komki-tresor
	@cd apps/komki_cli && MIX_ENV=prod mix deps.get >/dev/null && MIX_ENV=prod mix escript.build
	@rm -rf "$(KOMKI_PAKET)" && mkdir -p "$(KOMKI_PAKET)/lib/exqlite"
	@cp apps/komki_cli/komki apps/komki_cli/komki-tresor "$(KOMKI_PAKET)/"
	@cp -R apps/komki_cli/_build/prod/lib/exqlite/ebin apps/komki_cli/_build/prod/lib/exqlite/priv "$(KOMKI_PAKET)/lib/exqlite/"
	@cd packaging/pi && pnpm install --frozen-lockfile --prod --ignore-scripts >/dev/null
	@cp -R packaging/pi/node_modules "$(KOMKI_PAKET)/lib/node_modules"
	@rm -rf "$(KOMKI_PAKET)/lib/node_modules/.bin"
	@find "$(KOMKI_PAKET)/lib/node_modules" -type d -path '*/prebuilds/*' ! -path '*/prebuilds/*/*' ! -name darwin-arm64 -exec rm -rf {} +
	@tar -C dist -czf "$(KOMKI_PAKET).tar.gz" "$(notdir $(KOMKI_PAKET))"
	@shasum -a 256 "$(KOMKI_PAKET).tar.gz"

# Formel aus der Vorlage: Adresse, Version und Pruefsumme des Pakets.
KOMKI_RELEASE_URL = https://github.com/croesnick/kommunalpolitik_ki/releases/download/komki-v$(KOMKI_VERSION)/komki-$(KOMKI_VERSION)-macos-arm64.tar.gz
define komki_formel
	sha=$$(shasum -a 256 "$(KOMKI_PAKET).tar.gz" | cut -d' ' -f1); \
	  sed -e "s|@URL@|$(1)|" -e "s/@VERSION@/$(KOMKI_VERSION)/g" -e "s/@SHA256@/$$sha/" packaging/homebrew/komki.rb.in > "$(2)"
endef

# Formel fuer ein GitHub-Release (Workflow komki-release)
komki-formel: komki-paket
	@$(call komki_formel,$(KOMKI_RELEASE_URL),dist/komki.rb)
	@echo "Formel geschrieben: dist/komki.rb"

# Lokaler Tap croesnick/tap (nur auf diesem Rechner, kein Remote): Paket bauen,
# Formel mit file://-Adresse in den Tap legen, per Homebrew (neu) installieren.
KOMKI_TAP = $(shell brew --repository)/Library/Taps/croesnick/homebrew-tap
komki-tap: komki-paket
	@mkdir -p "$(KOMKI_TAP)/Formula"
	@test -d "$(KOMKI_TAP)/.git" || git -C "$(KOMKI_TAP)" init -q
	@cp packaging/homebrew/TAP-README.md "$(KOMKI_TAP)/README.md"
	@$(call komki_formel,file://$(PWD)/$(KOMKI_PAKET).tar.gz,$(KOMKI_TAP)/Formula/komki.rb)
	@git -C "$(KOMKI_TAP)" add README.md Formula/komki.rb
	@git -C "$(KOMKI_TAP)" diff --cached --quiet || git -C "$(KOMKI_TAP)" commit -q -m "komki $(KOMKI_VERSION) (lokal gebaut)"
	@rm -f "$$(brew --cache croesnick/tap/komki 2>/dev/null)"
	@export HOMEBREW_NO_INSTALL_UPGRADE=1 HOMEBREW_NO_AUTO_UPDATE=1; \
	  if brew list --formula komki >/dev/null 2>&1; then brew reinstall croesnick/tap/komki; else brew install croesnick/tap/komki; fi

# Burrito-Einzeldatei (Ticket #181): komki mit eingebauter Laufzeit, fuer
# Rechner ohne Homebrew. Laufzeit = die laufende Erlang-Installation (Burrito
# hat fuer die aktuelle OTP-Version keine vorgebaute). Bau braucht zig 0.16.0
# und xz (docs/prerequisites.md). Ergebnis: dist/komki-<version>-macos-arm64-einzeldatei
KOMKI_ZIG ?= $(HOME)/.local/opt/zig-aarch64-macos-0.16.0
komki-burrito: komki-tresor
	@mkdir -p dist
	@cp apps/komki_cli/komki-tresor dist/komki-tresor
	@root=$$(erl -noshell -eval 'io:format("~s",[code:root_dir()]), halt().'); \
	  otp=$$(cat "$$root"/releases/*/OTP_VERSION | head -1); \
	  tar -czf dist/erts-$$otp-macos-aarch64.tar.gz -C "$$root" -s ",^\.,otp-$$otp-macos-aarch64," . ; \
	  cd apps/komki_cli && PATH="$(KOMKI_ZIG):$$PATH" MIX_ENV=prod BURRITO_TARGET=macos_silicon \
	    KOMKI_CUSTOM_ERTS="$(PWD)/dist/erts-$$otp-macos-aarch64.tar.gz" mix release --overwrite
	@cp apps/komki_cli/burrito_out/komki_macos_silicon "$(KOMKI_PAKET)-einzeldatei"
	@echo "Einzeldatei: $(KOMKI_PAKET)-einzeldatei (dist/komki-tresor gehört daneben)"

# Doku-Site lokal ansehen (docs/site/README.md). pnpm in der Version aus
# docs/site/package.json (packageManager), wie in der CI; fehlt es fuer die
# node-Version aus .tool-versions, hilft einmalig `corepack enable pnpm`.
DOCS_DIR = docs/site
DOCS_PNPM_CHECK = @cd $(DOCS_DIR) && pnpm --version >/dev/null 2>&1 || { \
	echo "pnpm fehlt fuer die node-Version aus .tool-versions."; \
	echo "Einmalig: corepack enable pnpm (mit asdf danach: asdf reshim nodejs)"; exit 1; }

# Live-Reload unter http://localhost:4321/kommunalpolitik_ki/
docs:
	$(DOCS_PNPM_CHECK)
	@cd $(DOCS_DIR) && pnpm install --frozen-lockfile && pnpm dev

# dist/ bauen wie in der CI (.github/workflows/pages.yml)
docs-build:
	$(DOCS_PNPM_CHECK)
	@cd $(DOCS_DIR) && pnpm install --frozen-lockfile && pnpm build

# dist/ so ansehen, wie GitHub Pages es ausliefert
docs-preview: docs-build
	@cd $(DOCS_DIR) && pnpm preview

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
