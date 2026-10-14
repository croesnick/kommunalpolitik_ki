# Findings: Web-Recherche-Optionen in der seatbelt-gesandboxten pi-Session

- **Ticket**: https://github.com/croesnick/kommunalpolitik_ki/issues/95
- **Abrufdatum of all web evidence**: 2026-10-14 (unless noted otherwise)
- **pi pin**: `@earendil-works/pi-coding-agent` 1.0.0 (per ticket context). The npm-global install on this machine currently reads **1.1.0** (local anchor: `/Users/crn/.asdf/installs/nodejs/24.11.1/lib/node_modules/@earendil-works/pi-coding-agent/package.json`). Version-precise claims cite the `v1.0.0` GitHub tag where they differ from 1.1.0; the drift is recorded in §6.
- **Method**: read-only. Repo facts from `apps/komki_cli` and `docs/rfcs/0003-vertrauliche-ki-arbeitsraeume.md`; pi facts from the locally installed bundle's docs plus the `v1.0.0` tag on GitHub; MCP-connector facts from vendor/npm/GitHub pages.

## 1. Does pi 1.0.0 ship a websearch tool? — No.

**Primary source**: npm package `@earendil-works/pi-coding-agent`, repo `earendil-works/pi` (formerly `badlogic/pi-mono`; the changelog's issue/PR links still point at `badlogic/pi-mono`), author Mario Zechner. The komki-relevant local binding: `apps/komki_cli/lib/komki_cli/config.ex` line 67 pins `"node_modules/@earendil-works/pi-coding-agent/dist/bundle/cli.js"`.

**Built-in tool set (version-precise, v1.0.0 tag)** — the v1.0.0 settings doc states:

> "Available built-in tools are `read`, `bash`, `powershell`, `edit`, `write`, `grep`, `find`, and `ls`."

> — https://github.com/earendil-works/pi/blob/v1.0.0/packages/coding-agent/docs/settings.md, quoted via Context7 `/earendil-works/pi/v1.0.0`, retrieved 2026-10-14

No `websearch`/`web_search` tool exists among them; the v1.0.0 CLI doc (https://raw.githubusercontent.com/earendil-works/pi/v1.0.0/packages/coding-agent/docs/cli.md, fetched 2026-10-14) shows the same table plus two inactive built-in *extension* tools (`codemode`, `tool_search`), neither network-capable. **Web search for pi therefore always arrives as an *addition*, never as a built-in to disable.**

**The vendor's own web-search path is a skill, not a tool**: the separate repo `badlogic/pi-skills` ships a `brave-search` skill driven through the **bash tool**, needing a shell env credential and a prior `npm install` in the skill directory:

> "Requires a Brave Search API account with a free subscription. A credit card is required to create the free subscription (you won't be charged). … export BRAVE_API_KEY="your-api-key-here" … Install dependencies (run once): cd {baseDir} && npm install"

> — https://github.com/badlogic/pi-skills/blob/main/brave-search/SKILL.md, fetched 2026-10-14

Dead on arrival inside the komki Arbeitsraum, three independent counts: (a) komki's `--tools read,write,ls[,find,grep]` omits the `bash` tool (`apps/komki_cli/lib/komki_cli/pi.ex`, `tools_list/1`) — the agent cannot run the skill's scripts; (b) the scripts would run inside the sandbox, which deny-defaults all outbound TCP except `(allow network-outbound (remote tcp "localhost:<port>"))` (`apps/komki_cli/lib/komki_cli/profile.ex` line 99) — no reach to `api.search.brave.com`; (c) `BRAVE_API_KEY` inside the sandboxed process environment puts a credential in the Arbeitsraum, exactly what RFC 0003 R.4.3 forbids. Same argument applies to any curl/lynx-class access attempted by the agent itself.

**Where pi *can* carry a mediated web connector: MCP.** Version-precise for the v1.0.0 tag:

> "Pi connects to [Model Context Protocol](https://modelcontextprotocol.io) servers over stdio or streamable HTTP and makes their tools and resources available to the model."

> — packages/coding-agent/docs/mcp.md; Context7 attributes the matching snippet to `pi/blob/v1.0.0/packages/coding-agent/docs/mcp.md` (retrieved 2026-10-14); the sentence as quoted is from the installed 1.1.0 doc (local: package docs/mcp.md line 3), passage unchanged.

Config lives in the agent dir's `mcp.json` — under komki's isoliertes HOME that is `pi-home/.pi/agent/mcp.json` — in the shared `mcpServers` shape, with per-server `exposure` (`direct`/`codemode`/`deferred`/`hidden`) and per-tool `toolExposure` overrides: pi-native Fassung-enforcement surface.

**Interaction with komki's flags (the central pragmatic blocker)**: komki passes `--no-extensions`. In the v1.0.0 CLI doc:

> "- `-ne`, `--no-extensions`<br>Disables discovered, configured, and built-in extensions. Explicit `-e` paths still load, so `pi -ne -e builtin:mcp` keeps only the built-in MCP support."

> — https://raw.githubusercontent.com/earendil-works/pi/v1.0.0/packages/coding-agent/docs/cli.md, fetched 2026-10-14

So pi 1.0.0's MCP support is a *built-in extension* and `-ne` turns it off; one added flag (`-e builtin:mcp`) re-enables it while keeping the rest of the `--no-extensions` hardening. (`--no-mcp`, present in 1.1.0, is **not** in the v1.0.0 CLI doc — version-precise distinction.)

**Proxy**: pi 1.0.0 supports HTTP(S) proxies for its own HTTP clients:

> "Added HTTP proxy environment variable support for API requests ([#942](https://github.com/badlogic/pi-mono/pull/942))"

> — packages/coding-agent/CHANGELOG.md, v1.0.0 section, quoted via Context7, retrieved 2026-10-14

and

> "`HTTP_PROXY`, `HTTPS_PROXY` | Proxy outbound HTTP requests"

> — https://raw.githubusercontent.com/earendil-works/pi/v1.0.0/packages/coding-agent/docs/environment-variables.md, fetched 2026-10-14

Caveats: these govern pi's *own* HTTP clients (in komki, that means the llama-server traffic, which should stay direct); and `--offline` ("Disables automatic network activity, including model catalog refreshes. Equivalent to `PI_OFFLINE=1`", same file) is a behavioral switch, **not** a network fence — the fence is the Seatbelt profile. A proxy is *available* as mediation but unnecessary if the connector exposes MCP on localhost directly (§4).

**Disable/replace summary**: no built-in websearch to disable; web search is entirely additive via skills (keep `--no-skills`-disabled, as komki does today) or MCP servers (file-configured, per-run re-enabling via explicit flag, per-tool exposure control in `mcp.json`).

## 2. MCP search servers as connector processes

Verified 2026-10-14. Relevant topology question: which can run **host-side**, license-clean, behind a Vermittler boundary, with a pin-down-able tool surface?

| Candidate | Transport / hosting | Credential | License | Tool surface | Notes / limits |
|---|---|---|---|---|---|
| **Brave** `brave/brave-search-mcp-server` (npm `@brave/brave-search-mcp-server` v2.1.4) | **stdio default, `--transport http` supported** → can run host-side as localhost HTTP MCP | `BRAVE_API_KEY` env | MIT | web, images, videos, news, local/place, AI summaries | brave.com/search/api (fetched 2026-10-14): Search plan "$5 per 1,000 requests", **"Includes $5 in free credits every month"** (≈1,000 free searches/month), "50 queries per second"; credit card required "only … to confirm your identity and will not be charged." |
| **Tavily** `tavily-ai/tavily-mcp` | remote HTTP (`https://mcp.tavily.com/mcp/`) or local `npx tavily-mcp` | `TAVILY_API_KEY` ("TAVILY_API_KEY environment variable is required", src/index.ts) or OAuth; **keyless** mode via header `X-Tavily-Access-Mode: keyless` | MIT | tavily-search, tavily-extract, map, crawl | Free API key "1,000 credits/month, no credit card" (docs.tavily.com, fetched 2026-10-14). Keyless: "free and rate-limited" — numbers **unverified**. |
| **SearXNG** `mcp-searxng` (npm, ihor-sokoliuk) | stdio server → SearXNG instance | none — requires "an existing SearXNG instance with JSON search enabled" | MIT | web search, suggestions, web_url_read | Self-hosting burden; SearXNG itself queries upstream engines. `teran/mcp-searxng` (Apache-2.0, Go) natively offers stdio **and** Streamable HTTP with rate limiting. |
| **Exa** exa-mcp-server | vendor-hosted / local | API key | — | web search, related | **Not primary-verified**; only via `mcp-searxng` README comparison: Exa — Web Search ✓, Self-hosted ✗, Free/No API key ✗. |

Fassung problem common to all: they advertise *more* than search (Tavily crawl/map; Brave local/search/summarizers). Either pi-side `toolExposure` pins the allowed tool (`hidden` server + one `direct` tool), or the connector is implemented to a single operation. R.4.3 makes the gap lethal if unmanaged:

> "Der Funktionsumfang eines Connectors — welche Operationen er tatsächlich anbietet und mit welchen Parametern sich jede Operation aufrufen lässt — wird in einer festen Fassung festgehalten. Ändert er sich, entsteht eine neue, gekennzeichnete Fassung, statt die alte still umzuschreiben. … Bietet der Connector in Wirklichkeit mehr oder weniger als eingetragen, lautet die betroffene Entscheidung `indeterminate`."

> — docs/rfcs/0003-vertrauliche-ki-arbeitsraeume.md, R.4.3, lines 544 (and the credentials line 538), reviewed this session

## 3. Local CLI options (ddgr / googler-class / lynx-w3m-class)

- **ddgr** (jarun/ddgr, GPLv3, Python ≥3.8): last release **v2.2, 2023-12-29** (https://github.com/jarun/ddgr/releases/tag/v2.2). Per its own description it searches "DuckDuckGo (html version)" (https://pypi.org/project/ddgr/, fetched 2026-10-14) — HTML scraping, no API contract; supports `--proxy` and `--json`. Works today in the common case; breaks whenever DuckDuckGo changes markup/bot defenses. Any in-sandbox use would additionally require adding python exec plus outbound-to-remote-host rules to the deny-default profile — a far wider drift than one localhost port literal.
- **googler**: maintenance status could not be verified this run. Community reports ("googler … was great but google seem to have crippled it") suggest it is defunct. **Unverified** — listed for completeness only.
- **lynx/w3m/links pipelines**: fetch/render pages, but search-engine use is uncontracted scraping (captcha/JS/policy walls); same profile-drift objection, no API semantics, no quota surface. Verdict as assessment (not a measured failure): unsuitable as the mediated path.

All local-CLI options share the decisive flaw: they make the **agent's process** touch the network — precisely what RFC 0003 §6/R.4.3 routes through the Vermittler. No scenario where they beat an MCP connector on policy-vermittelbarkeit, and they lose on robustness too.

## 4. Outbound/inbound mechanics for a minimal viable web connector

Normative model (docs/rfcs/0003-vertrauliche-ki-arbeitsraeume.md):

- §6, lines 148–150 (occurrence of an empty request is an output — existence leak):
  > "Eine Anlage fordert den Agenten auf, nur beim Wort „Klage" einen leeren Webrequest zu senden. Der Request enthält keinen geheimen Satz. Sein Auftreten verrät trotzdem ein Merkmal der Vorlage. Deshalb erfasst das Modell das ganze **Ereignis**: Payload, Auswahl, Ziel, relevante Metadaten und tatsächliches Auftreten."
- §7, lines 198–201 (two directions, Bindung of the outbound):
  > "Ein Abruf hat zwei Prüfungsrichtungen. **Auswärts** sind **Suchtext, Dokumentkennung und Aufrufentscheidung Ausgaben**. **Einwärts** ist die klassifizierte Antwort ein **neuer Eingang**. Leseberechtigung für die Antwort ist keine beliebige Sendeberechtigung für die Anfrage."
- R.4.3, line 538 (credentials at the Connector):
  > "Connectoren vermitteln begrenzte Operationen an Quellen und Zielen. Credentials bleiben beim Connector. Sie werden dem Agenten weder als Datei noch als Werkzeugantwort, Fehler oder Log zugänglich gemacht."
- R.4.4, line 548 (only the Vermittler creates external effects):
  > "Ein verbindlicher Vermittler prüft und führt Operationen aus. … Nur dieser kontrollierte Weg darf tatsächliche Außenwirkungen erzeugen."

Mechanically in komki today:

1. **Network surface**: exactly one outbound literal, `(allow network-outbound (remote tcp "localhost:<port>"))` for llama-server (profile.ex line 99). The profile is byte-identical for fixed inputs (determinism guarantee, profile.ex moduledoc lines 15–22) — adding a **second localhost-port literal** is a one-line, fully visible, regenerable change of an already-validated rule class. No host wildcards, no remote hosts.
2. **Two topologies**:
   - **(a) Connector host-side; pi connects MCP-over-HTTP (`url`) to `http://localhost:<connector-port>/mcp`** — mirrors the llama-server pattern. The credential (`BRAVE_API_KEY`) stays with the host-side connector, outside the Arbeitsraum; the sandboxed pi sees only tool schemas. Profile cost: one literal.
   - (b) Connector as stdio child *inside* the sandbox: needs new `process-exec` allowlist entries for the connector binary chain, file-read chain entries for its install tree, plus — decisive — outbound to a *remote* search API host (a rule class the profile deliberately lacks), and the credential would live (at least as env) inside the sandboxed process subtree. Strictly worse on every axis. Discarded.
3. **Outbound (bound output)**: pi's tool call against `mcp__websearch__<tool>` carries the query text with its full Bindung. The Vermittler (host-side connector) records verbatim query, target, decision, and Abrufdatum **before** dispatching upstream (Journal-Writer discipline per R.4.4). §6 is satisfied because the log item exists even for failed or empty queries.
4. **Inbound (classified input)**: the upstream response returns over the same localhost stream into the Arbeitsraum — a new input whose admission is decided by the connector, not the agent. For this prototype a deterministic rule suffices (source = the one approved search API → admitted as public, labelled with Abrufdatum + URL, recorded in the Journal; anything outside the Fassung → refuse). Honest limitation: pi receives the response directly in context; pi 1.0.0 has no built-in quarantine stage, so "classification before admission" is enforced **procedurally** in the Vermittler (log, label, refuse-by-default), not as a technical hold buffer. This must be documented as a benannte Grenze (cf. D.9 `grenzdurchsetzung`: "Host-Loopback … werden blockiert oder als benannte Grenze dokumentiert").
5. **Credentials**: never in the sandbox-side `mcp.json` under topology (a) — the local HTTP entry needs no auth; the upstream `BRAVE_API_KEY` is an env var of the host-side connector only. ("Credentials bleiben beim Connector.")
6. **Fassung enforcement pi-side** (without touching connector code): in `pi-home/.pi/agent/mcp.json`, set server `exposure: hidden` with `toolExposure` granting exactly the web-search tool as `direct`; record that pinned operation set as the connector's feste Fassung (Environment-Datensatz per B.3). Pi additionally routes MCP calls through its tool pipeline, which allows a permission gate now or later: "Every MCP call passes through Pi's tool pipeline. Extension `tool_call` and `tool_result` handlers, including permission gates, therefore apply to MCP tools." (installed docs/mcp.md).

## 5. Recommendation

**Run the official `brave/brave-search-mcp-server` (npm `@brave/brave-search-mcp-server`, MIT) host-side in HTTP transport as the Vermittler's first web connector**; the sandboxed pi reaches it as one extra localhost port rule:

1. **Host side**: Brave Search API ("Search" plan; $5 in free monthly credits ≈1,000 free searches/month; credit card only as anti-fraud identity check); pre-install the npm package on the host (no runtime fetching), then run `npx @brave/brave-search-mcp-server --transport http` with `BRAVE_API_KEY` in its env, bound to a fixed localhost port (analogous to llama-server's 49524).
2. **`profile.ex`**: add one more literal `(allow network-outbound (remote tcp "localhost:<connector-port>"))` — same rule class as the llama port; byte-identical regeneration preserved since both literals derive from config.
3. **`pi-home/.pi/agent/mcp.json`**: one HTTP server entry for the connector, `exposure: hidden` + `toolExposure` granting exactly the web-search tool as `direct`; record that pinned operation set as the connector's feste Fassung.
4. **`pi.ex` session flags**: add `-e builtin:mcp` next to the existing `--no-extensions` (v1.0.0-verified, quote below) so only the built-in MCP support is re-enabled; check the installed Fassung for whether `--tools` needs an `mcp__` entry (that special-casing is documented for 1.1.0; 1.0.0 behavior **unverified**).
5. **Vermittler discipline**: log-before-dispatch (verbatim query, tool, timestamp, Abrufdatum); deterministic inbound classification (approved API → public, labelled; else refuse); Journal entry per call — satisfying §6 (even empty/failed requests are logged) and §7's two-direction rule.

Why this one: zero credentials inside the Arbeitsraum; one-claim network profile change; vendor-maintained MIT server (no new connector code for the MVP); low latency with 50 qps capacity; German-capable results (`--country DE` on the API — hence via Brave's class of interface, same as the pi-skills `search.js --country DE` surface); stable free tier matching a Stadtrat-session workload (≈1,000 searches/month). Fassung keeps it narrow: search only — the Agent's Leseberechtigung für Antworten is not a Sendeberechtigung für Crawl/Extract; page extraction later becomes a separate connector decision, not a silent widening of this one.

Elixir-first caveat: a hand-rolled Elixir MCP connector (e.g. on `anubis_mcp`, already in use in `ratsprojekte`) would fit repo principles even better and shrink the dependency surface; it costs implementation time the MVP should not spend now. It is the natural consolidation step once the Brave-MCP route proves the workflow.

## 6. Evidence limits

- Brave price/rate figures are vendor marketing pages, restated verbatim, not independently metered.
- Tavily keyless rate-limit numbers: not published in my sources; **unverified**.
- Whether Brave's older "Free AI" subscription model (referenced in pi-skills' SKILL.md) still exists in current signup flows is unclear; today's brave.com page shows the $5-credits model. Abrufdatum 2026-10-14.
- Exa MCP: only third-party comparison table; not primary-verified.
- lynx/w3m/ddgr scrape fragility is an assessment, not a measured failure.
- **Version drift**: installed pi bundle is 1.1.0; pin per ticket context is 1.0.0. All 1.0.0-tagged quotes are from the v1.0.0 tag; hints taken from installed 1.1.0 docs (e.g. `mcp__` filtering of `--tools`, `--no-mcp` flag) are marked as not re-verified against 1.0.0 where relevant.
- googler: status **unverified**.

## 7. Load-bearing quotes with anchors

All URLs fetched 2026-10-14 unless noted.

1. **pi 1.0.0 tool list** (source `github.com/earendil-works/pi/blob/v1.0.0/packages/coding-agent/docs/settings.md` via Context7): "Available built-in tools are `read`, `bash`, `powershell`, `edit`, `write`, `grep`, `find`, and `ls`."
2. **pi 1.0.0 MCP re-enable path** (raw tag file `…/v1.0.0/packages/coding-agent/docs/cli.md`): "- `-ne`, `--no-extensions`<br>Disables discovered, configured, and built-in extensions. Explicit `-e` paths still load, so `pi -ne -e builtin:mcp` keeps only the built-in MCP support."
3. **pi MCP over HTTP** (installed docs/mcp.md line 3; same sentence attributed to the v1.0.0 file via Context7): "Pi connects to [Model Context Protocol](https://modelcontextprotocol.io) servers over stdio or streamable HTTP and makes their tools and resources available to the model."
4. **RFC 0003 §7, lines 198–201** (repo): "Ein Abruf hat zwei Prüfungsrichtungen. Auswärts sind Suchtext, Dokumentkennung und Aufrufentscheidung Ausgaben. Einwärts ist die klassifizierte Antwort ein neuer Eingang."
5. **RFC 0003 R.4.3, line 538** (repo): "Connectoren vermitteln begrenzte Operationen an Quellen und Zielen. Credentials bleiben beim Connector. Sie werden dem Agenten weder als Datei noch als Werkzeugantwort, Fehler oder Log zugänglich gemacht."

Additional anchors used inline: R.4.3 line 544 (feste Fassung), R.4.4 line 548, RFC 0003 §6 lines 148–150, pi-skills brave-search SKILL.md and README, Brave plan page + npm page, Tavily docs, ddgr release tag, pi v1.0.0 environment-variables.md and CHANGELOG, komki `profile.ex` line 99 / `pi.ex` tools_list.
