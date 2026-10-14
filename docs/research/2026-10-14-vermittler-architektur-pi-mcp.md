# Vermittler architecture: How pi's tool calls pass through the policy engine — research findings

- **Ticket:** https://github.com/croesnick/kommunalpolitik_ki/issues/90 (context pointer)
- **Date:** 2026-10-14 (all external anchors checked on this date; local code inspected on this date)
- **Question:** By what mechanism does komki check every tool call from pi *before* its effect (Gate 1) and every response *before* it is admitted into context (Gate 2)?
- **Method:** Local source inspection (`apps/komki_cli`, `apps/komki_policy`, RFC 0003, calibration report), plus primary-source inspection of the pinned coding agent pi (installed npm artifact + repository docs at tag `v1.0.0`). Every load-bearing claim carries a verbatim quote plus an anchor. Unverified items are listed explicitly at the end, never presented as fact.

## 0. Answer in one paragraph

**Today, no such mechanism exists.** Pi's tool calls are confined by the macOS Seatbelt profile (deny-default, allowlisted executors, only `localhost:49524` outbound), but nothing evaluates a proposed call against komki_policy before pi dispatches it, and nothing re-judges a tool result before pi places it in context. Pi offers three real seams for a Vermittler, all verified at the pinned version: (a) its native MCP client — pi connects to MCP servers over stdio or streamable HTTP, and *every* MCP call can be gated inside the server process, outside the agent; (b) its extension hooks (`tool_call` can block execution, `tool_result` can redact before context) — but extensions run inside the pi process, so they cannot themselves be the RFC's Vermittler; (c) the Seatbelt profile itself — an OS-level boundary, not a label calculus. Recommendation: run the Vermittler as an Elixir MCP server on a second, profile-allowlisted loopback port (Gate 1 and Gate 2 in the server handlers, PDR records per call), keep the Seatbelt profile as the Grenzdurchsetzung layer, and close the residual built-in-`read`/`write` gap in a second phase with a dumb-forwarder extension under `--no-builtin-tools`.

## 1. Local state: how komki launches pi today

All quotes from local files verified by inspection, abreufdatum 2026-10-14.

**The launch chain** (`apps/komki_cli/lib/komki_cli/pi.ex:249-261`):

> ```elixir
> [
>   cfg.sandbox_exec,
>   "-f",
>   profile_path,
>   "--",
>   "/bin/sh",
>   "-c",
>   ~s(exec "$0" "$@" < /dev/null),
>   cfg.node_bin,
>   cfg.cli_js
> ] ++
>   pi_flags(mode, scratch_dir) ++
>   [prompt]

Anchor: `/Users/crn/projects/kommunalpolitik_ki/apps/komki_cli/lib/komki_cli/pi.ex`, lines 249–261 (`KomkiCli.Pi.argv_for/4`, "argv fuer den sandbox-exec-Aufruf").

**The pi flags** (`pi.ex:204-225`):

> ```elixir
> "--print", "--mode", Atom.to_string(mode), "--offline",
> "--no-extensions", "--no-skills", "--no-prompt-templates", "--no-themes",
> "--no-approve", "--no-session",
> "--session-dir", Path.join(scratch_dir, "pi-sessions"),
> "--tools", "write",
> "--provider", "pi-local", "--model", "local-model"

Anchor: same file, `pi_flags/2`. The interactive session (`session_flags/2`, lines 156–184) uses the same disable-flags *without* `--no-approve` (the code comment explains: the flag would force "untrusted" behavior) and a wider tool allowlist:

> ```elixir
> "--tools", tools_list(cfg),  # ["read", "write", "ls"] ++ fd/rg when discovered

Crucially, **`bash`, `edit`, `codemode` and `tool_search` are never enabled** — the tool allowlist is the first de-facto filter: no shell tool means the model cannot spawn processes, and no `codemode` means no indirect tool calls.

**Environment containment** (`pi.ex:229-242`): `HOME=pi-home`, `PATH=/usr/bin:/bin`, `PI_OFFLINE=1`, XDG dirs inside pi-home.

**The Seatbelt profile** (`apps/komki_cli/lib/komki_cli/profile.ex`): `(deny default)` basis ("Garantien ... `(deny default)` Basis; niemals `(allow default)`, keine Host-Wildcards", lines 16–18); exec allowlisted literals for node, the pi launcher, and the fd/rg copies in pi's agent-bin fundus (lines 148–177); file scopes limited to pi-home and the scratch directory ("isolated HOME ... + Scratch-Write-Scope", lines 394–401); and exactly one network rule:

> `"(allow network-outbound (remote tcp \"localhost:" <> port <> "\"))"`

Anchor: `profile.ex:11` and `profile.ex:99` — the single network exception is the llama-server loopback port.

**Boot gate:** `apps/komki_cli/lib/komki_cli/steps.ex` produces a `summary_state ∈ :ok | :fail | :boot_gate_fail` (lines 14–16) and verifies the pinned GGUF ("gguf-sha256: <actual> (pinned, verified)", lines 161–162). The session chain keeps `sandbox-exec` first ("`session-chain` haelt die Seatbelt-Grenze unverletzt: sandbox-exec bleibt der Anfang des gepinnten Kettenstücks", `pi.ex:140-141`).

**Assessment against the question:** The profile answers *where* (paths, executors, ports) but not *whether* — no call to `komki_policy` sits on the dispatch path, and a tool result flows from the tool straight into pi's context without any judgment step. The seams that exist today for a mediator: the profile generation itself (a second loopback port rule for a mediator is a one-line addition), the tool allowlist (shrink it), and the flag set (add `-e <shim>` without weakening `-ne`, see §2.4).

## 2. Pi's primary sources at the pinned version 1.0.0

Installed artifact: `/Users/crn/.asdf/installs/nodejs/24.11.1/lib/node_modules/@earendil-works/pi-coding-agent` — `package.json`: `"name": "@earendil-works/pi-coding-agent", "version": "1.1.0"`. **Discrepancy:** the repo's research decision pinned pi 1.0.0 (`docs/research/2026-10-04-probe-harness-sandbox.md:163`: "Versionen: OpenCode 1.18.34, pi 1.0.0"), but the artifact on this host is now 1.1.0 (npm-installed without transitive pinning keeps floating). All version-1.0.0 claims below were checked against the repository docs at tag `v1.0.0` and are corroborated by the shipped CHANGELOG's feature timeline (see §5, Unverified). Canonical repository: `github.com/earendil-works/pi` (the fetched page of the old `badlogic/pi-mono` URL serves the earendil-works repo — GitHub redirect observed).

### 2.1 Built-in tools (v1.0.0)

> | Built-in | Purpose |
> |---|---|
> | `read` | Read text files and supported images |
> | `bash` | Run shell commands |
> | `powershell` | Run PowerShell commands on Windows |
> | `edit` | Apply exact text replacements to an existing file |
> | `write` | Create or overwrite a file |
> | `grep` | Search file contents |
> | `find` | Find paths using glob patterns |
> | `ls` | List directory contents |

Anchor: `packages/coding-agent/docs/cli.md` at tag `v1.0.0`, table under "Tool options" (raw.githubusercontent.com/earendil-works/pi/v1.0.0/packages/coding-agent/docs/cli.md, fetched 2026-10-14). Actor quote: "Default enabled tools are `read`, `bash`, `edit`, and `write`, unless `defaultTools` changes them." Command-line selection flags: `-t/--tools` (allowlist), `-xt/--exclude-tools`, `-nbt/--no-builtin-tools` ("Disables default built-in tools while retaining extension and custom tools."), `-nt/--no-tools`.

### 2.2 No websearch tool

No built-in `websearch`/`web_search`/`web-fetch`-style tool exists in the v1.0.0 tool table above, and no such tool appears anywhere in the shipped v1.0.0 docs set. The only network-capable built-in is `bash`; opening the network without it would require the (normal) pi process exchanging data — with `--offline`/`PI_OFFLINE` muzzling model-catalog refreshes only, not arbitrary sockets. **For komki this is moot: `bash` is not in komki's tool allowlist and the profile permits only `localhost:49524` outbound.** Consequence for the Vermittler: the only *sanctioned* data channel komki needs to police is the one it adds itself (MCP to the mediator) plus the sandbox-scoped file reads. Not independently re-verified against the v1.0.0 source tree — the docs set is the evidence basis.

### 2.3 MCP support (v1.0.0) — pi is an MCP *client*

> "Pi connects to [Model Context Protocol](https://modelcontextprotocol.io) servers over stdio or streamable HTTP and makes their tools and resources available to the model."

Anchor: `packages/coding-agent/docs/mcp.md` at tag `v1.0.0` (raw URL as above, fetched 2026-10-14). Mechanism details, all v1.0.0 verbatim:

- Config: user-level `~/.pi/agent/mcp.json`, project `.pi/mcp.json` (project one only read "after project trust is granted" — komki runs headless under `-ne`, so effectively only the user-level file matters, and pi-home *is* the `HOME`).
- Tools are namespaced: "Tools are named `mcp__<server>__<tool>`", and exposure modes `codemode` (default), `deferred`, `direct`, `hidden` control what the model sees ("`direct` | Declared to the model like a built-in tool and also callable from codemode.").
- Transport: "HTTP servers use `url`, `headers`, and `oauth` ... The legacy SSE transport is not supported." Stdio servers are spawned from `command`/`args`/`env`/`cwd`.

**How to enable it without enabling anything else (the key for komki):**

> "Pi requires a project-trust decision ..." — user-level resources need no trust; and:

> "`-ne`, `--no-extensions` — Disables discovered, configured, and built-in extensions. Explicit `-e` paths still load, so `pi -ne -e builtin:mcp` keeps only the built-in MCP support."

Anchor: `docs/cli.md` at tag `v1.0.0`, "Resource options". So MCP support is a **built-in extension** (`builtin:mcp`); komki's current `-ne` turns it off, and it can be re-enabled *singly* by appending `-e builtin:mcp` — every other extension stays dead. No `--no-mcp` flag and no `mcp__` tool patterns exist at 1.0.0 (both were added in 1.0.4 per the shipped CHANGELOG: "Added `--no-mcp` to disable the built-in MCP support for one run", `CHANGELOG.md:65` in the installed 1.1.0 artifact).

### 2.4 Hooks and wrapping seams (v1.0.0)

Extensions are the programmatic seam — with a hard architectural caveat:

> "An extension runs inside the Pi process with the same operating-system permissions. It can inspect prompts, tool calls, files, credentials, and session history, so load extensions only from sources you trust."

> "`tool_call` can mutate input or block execution. `tool_result` handlers compose, with each handler seeing prior changes."

> "Pi reports handler errors and continues where possible. A `tool_call` handler failure blocks the tool as a fail-safe; a tool execution failure becomes an error result for the model."

> ```typescript
> if (needsApproval && !(await ctx.ui.confirm("Allow tool call?", event.toolName))) {
>   return { block: true, reason: `${event.toolName} was not approved` };
> }
> ```

Anchor: `docs/extensions.md` at tag `v1.0.0` (fetched 2026-10-14). Custom tools: "A custom tool defines a name, model-facing description, TypeBox parameter schema, and `execute()` function." Nested calls also pass the hooks ("Nested calls go through argument validation and the `tool_call` and `tool_result` handlers like model-issued calls"). MCP calls pass through the same pipeline: "Every MCP call passes through Pi's tool pipeline. Extension `tool_call` and `tool_result` handlers, including permission gates, therefore apply to MCP tools." (`mcp.md` v1.0.0, "Permissions").

**Consequence:** the hooks are a complete *mechanical* interception point (block, mutate, redact — plus fail-closed), but an in-process extension is **inside agent authority** and can never be the RFC's Vermittler itself. It can only be a forwarding shim *in front of* an external Vermittler, or nothing.

### 2.5 Version-1.0.0 deltas that constrain komki's flags

From the shipped CHANGELOG (installed artifact, `CHANGELOG.md`, all entries verbatim):

- `--no-mcp`, `mcp__` tool patterns in `--tools`/`--exclude-tools`: added **1.0.4** (2026-10-05) — not available at the pin.
- `+name`/`-name` entries in `--tools`: added **1.1.0** (2026-10-07) — not available at the pin.
- At the pin, `-ne -e builtin:mcp` is the only selective way to turn MCP on while keeping everything else off.

## 3. Normative anchors

- **R.4.3**: "Connectoren vermitteln begrenzte Operationen an Quellen und Zielen. Credentials bleiben beim Connector. Sie werden dem Agenten weder als Datei noch als Werkzeugantwort, Fehler oder Log zugänglich gemacht." — "Der Funktionsumfang eines Connectors ... wird in einer festen Fassung festgehalten. ... Bietet der Connector in Wirklichkeit mehr oder weniger als eingetragen, lautet die betroffene Entscheidung `indeterminate`." (docs/rfcs/0003-vertrauliche-ki-arbeitsraeume.md, R.4.3, lines 536–544; inspected 2026-10-14).
- **R.4.4**: "Ein verbindlicher Vermittler prüft und führt Operationen aus. ... Nur dieser kontrollierte Weg darf tatsächliche Außenwirkungen erzeugen." (same file, lines 546–548).
- **Vermittler independence**: "Der **Vermittler** ist eine vom Agenten unabhängige Komponente, die Operationen prüft und ausführt." (same file, line 158).
- **Dual-phase + PDR pattern** (calibration doc, move 2, verbatim): "Check the exact rendered call before dispatch, check the return before admission, and bind each decision record to the intent hash, the payload hash, and a Γ snapshot hash." (docs/research/2026-10-13-agent-policy-models-openappa-pace.md, line 157; inspected 2026-10-14). The APPA reference-monitor half of the same doc: "Gate 1 checks every tool call before dispatch against the label the call would produce ... Gate 2 re-verifies the realized return before it enters the model's context." (line 23).

## 4. Three mediation options compared

### Option A — komki-side tool proxy that pi must call through (forwarder extension)

Mechanism: launch pi with the existing `-ne` **plus** an explicit `-e /path/to/komki-shim.ts` (v1.0.0-verified feasible: explicit loads survive `-ne`) and `--no-builtin-tools`; the shim registers `komki_read`, `komki_write`, `komki_*` as direct custom tools that forward each call over loopback HTTP to the komki BEAM. Gate 1 and Gate 2 both live in the BEAM: `komki_policy.validate/decide` on the exact rendered call, execute with host credentials, filter/label the result, write a PDR.

- **Enforces:** complete dual-phase mediation over the *entire* declared surface (built-ins disabled ⇒ every content byte in or out of context transits the mediator). Urteil (komki_policy, pure) separated from Vollzug (BEAM executes) — clean B.8 shape.
- **Cannot enforce:** nothing about what the pi process does below the tool layer that the shim does not see — but the sandbox's exec allowlist (node, pi, fd, rg copies only; no bash tool) already bounds that.
- **Bypass surface:** (a) the shim itself is a komki-authored component inside the agent process; if it stops being a dumb forwarder, judgment happens inside agent authority. Mitigate by contract: the shim must hold no policy logic and only one TLS-less loopback endpoint, and every PDR the mediator emits is the receipt that a check *happened* outside; (b) the model can `read` any file in pi-home scope — including any shim source installed there (defense: keep shim outside pi-home; `read` scope is pi-home + scratch, so place the shim at the komki base dir and pass an absolute `-e` path from outside).
- **Credential exposure:** none in the sandbox — the BEAM holds credentials outside pi's reach (satisfies R.4.3's "Credentials bleiben beim Connector").
- **Cost:** a TypeScript shim must be authored, pinned into the `Fassung`, and kept byte-stable across pi versions; komki must add a second loopback port rule.

### Option B — MCP server exposed to pi (viable: pi speaks MCP client-side, verified)

Mechanism: `-ne -e builtin:mcp` (single explicit load); komki writes `pi-home/.pi/agent/mcp.json` (user-level — effective under headless `-ne`) with `{"komki": {"url": "http://127.0.0.1:<mediator-port>/mcp"}}`; profile gains a second `network-outbound` localhost rule for the mediator port. Gate 1 = the MCP tool *handler* runs `komki_policy` on the exact rendered call (tool name + canonically serialized args) before performing the connector operation; Gate 2 = the handler filters/labels the return before sending the MCP response — what comes back is what pi places in the transcript. PDR per call.

- **Enforces:** Gate 2 *fully* for every mediated tool — in MCP, the server's response *is* the tool result; nothing between handler and context that could be unjudged. Gate 1 fully for mediated tools. Connector `Fassung` gets a natural home: each exposed MCP tool is one entry in the fixed Fassung per R.4.3; the `D.9` `connector-bypass` attack (a broader operation of the same server defeating a narrow one) is tested by pinning the tool list.
- **Cannot enforce:** the built-in `read`/`write`/`ls`/`find`/`grep` over sandbox scopes remain unmediated — scratch content enters context raw (see the Gate-2-wall discussion in §5). If `--no-builtin-tools` is added (v1.0.0 flag, verified), this option *becomes* option A's enforcement without a shim: the model's surface collapses to `mcp__komki__*` tools only; but then reading local files needs an MCP `read` too, which is fine (the mediator serves it from host FS).
- **Bypass surface:** (a) the model can rewrite `pi-home/.pi/agent/mcp.json` via built-in `write` and steer future restarts — bounded by the profile's port rules (only the two loopback ports; only node/pi/fd/rg exec), and the MCP tool surface still judged per call; (b) pi's own process is inside the sandbox and could speak to the mediator port in other ways — the only code running there is pi, which only emits MCP when servers are configured; residual risk noted honestly.
- **Credential exposure:** if the RIS/Nextcloud connectors ever need tokens, `-e builtin:mcp` means the config file lives in pi-home and the model can `read` it (pi-home is a read-allowed scope). Mitigation: start credential-free (RIS is public), and later pass credentials only inside the mediator process, keyed by server identity, never into mcp.json — or adopt OAuth with out-of-band flows. Bearer-token-in-mcp.json (`--bearer-token-env-var`, v1.0.0 verified) would place the token in pi-home and must not be used with komki.
- **Cost:** lowest. Elixir MCP server precedent exists in-repo (ratsprojekte exposes `/mcp` via `anubis_mcp`, per AGENTS.md tool table, inspected 2026-10-14).

### Option C — Seatbelt-mediated paths with connector processes

Mechanism: today's approach escalated — every connector becomes a separate, allowlisted executable with credentials in its env; SBPL rules gate which connectors exist and where files may flow; connectors call komki_policy themselves before acting (Gate 1) and sanitize their returns (Gate 2).

- **Enforces:** the OS boundary (Grenzdurchsetzung: D.9's "Raw Sockets, IPv6-, UDP- und DNS-Pfade ... werden blockiert" is literally what `(deny default)` + single-port rules deliver), plus a hard floor nothing above can exceed.
- **Cannot enforce:** the label calculus — SBPL knows paths and ports, never Empfängerkreis, Bindungen, or Offenlegungsstand; Gate 2 has no OS primitive (a returned byte can be anything); Gate 1 must be re-enabled *inside each connector in its own implementation language*, multiplying conforming-component surface linearly (each connector = a mini-mediator to test).
- **Bypass surface:** any allowlisted executor (fd/rg/node) can read every file in its allowed scopes — the sandbox is a scope contract, not a judgment; and the D.9 `connector-bypass` case (Fassung says narrow, binary does broad) is invisible to SBPL.
- **Credential exposure:** worst of the three — connectors spawned as pi-children inherit pi's environment for anything passed via `env`; credentials land inside the sandbox boundary even if only in child env.

### Verdict

B as the prototype, A as the closure, C as the permanent substrate. B wins on prototype speed, RFC conformance (the mediator process is genuinely outside agent authority and holds the Urteil–Vollzug split), and Elixir-first (an MCP server is exactly the artifact class komki already builds). Its one honest hole — unmediated built-ins — is closed by escalating to A's `--no-builtin-tools` shape once the mediator exists, rather than by writing SBPL rules that can never judge.

## 5. Minimal dual-phase mediator sketch (PDR pattern per calibration move 2)

Two processes, one boundary:

1. **komki-mediator** (Elixir, outside the sandbox; second loopback port; profile gains `(allow network-outbound (remote tcp "localhost:<mediator-port>"))`): exposes the connector Fassung as named MCP tools (`ris_search`, `ris_show`, …), each handler:
   - **Gate 1:** canonicalize the exact rendered call (*tool name + params, byte-stable JSON — komki_policy's §6 canonicalization exists precisely for this*), compute `intent_hash = SHA256(canon_call)`, call `KomkiPolicy.decide` against the room's Registry; on deny, return the APPA-style remedy plan (which fact/GO/workspace clears the gap — calibration move 1) instead of a bare error; on allow, emit a **PDR**: `{decision_id, tool, intent_hash, payload_hash (post-execution), gamma_hash (registry_id + content hash of registry.json — komki_policy already carries `registry_id`), outcome,Abrufdatum}`; only then perform the connector operation (Vollzug outside the sandbox).
   - **Gate 2:** filter/label the realized return against the same Γ stand (the realized payload, not the proposed one — "check the return before admission"), amend the PDR with `payload_hash = SHA256(return_bytes)` and `admitted: true|redacted`, and only then return the response. Pi's own pipeline re-runs `tool_result` hooks on it later, but judgment has already happened outside agent authority.
2. **komki policy + journal:** `komki_policy` stays the pure decider; the PDR journal gets the separate writer right that R.4.4 assigns ("Seine auditpflichtigen Schritte werden durch einen getrennt berechtigten Journal-Writer festgehalten"); `KomkiPolicy.verify` re-checks PDRs against the pinned Γ hash independently of `derive`.

**The honest Gate-2 wall:** per-call Gate 2 for pi's *built-in* `read`/`write` is not enforceable from outside the pi process at v1.0.0 — the only in-pi seam (`tool_result`) is inside agent authority. The RFC-conformant resolution is workspace-shaped: admission (R.5.4 Aufnahme) happens at the mediator when approved material is *placed* into the Arbeitsraum (scratch); built-in reads then operate only on the admitted envelope, and the label a file carries is the one the mediator assigned at admission. "Rename-or-launder" attacks (R.2.1: "Der Agent darf Labels weder vorschreiben noch weglassen") remain bounded by the sandbox's write scope, which covers exactly pi-home + scratch.

## 6. Recommendation (single)

**Adopt Option B now, as `apps/komki_mediator` (Elixir) exposing the first connectors as an MCP server**, launched by komki at `up` time on a dedicated loopback port; add the one-line Seatbelt rule for that port; enable pi's built-in MCP via the verified `-ne -e builtin:mcp` composition; keep every connector operation and every return behind `komki_policy` with PDRs bound to intent hash, payload hash, and Γ snapshot hash. Follow up (tracked ticket, not silent build-out per Ticket-Disziplin) with: (1) `--no-builtin-tools` + an `mcp__komki__read/write` pair so Gate 2 covers file admission too, leaving `bash`/`codemode` dead; (2) the Connector-Fassung record (fixed, versioned tool list) per R.4.3 and the D.9 connector-bypass plus D.1 regression tests; (3) resolution of the pin drift — the installed artifact is pi 1.1.0 while the research pin says 1.0.0; either re-pin deliberately at 1.0.0 (then no `--no-mcp`/patterns) or re-validate the flags in use on 1.1.x before the mediator ships on top of it.

## Evidence limits

- The **v1.0.0 tag claims** rest on two fetches against `raw.githubusercontent.com/.../v1.0.0/...`. The absent `--no-mcp`, absent tool patterns, and absent `+name`/`-name` in the fetched CLI doc exactly match the shipped CHANGELOG's 1.0.4/1.1.0 feature timeline, which is strong corroboration that the tag was actually served — but no git checkout of v1.0.0 was performed, and the source *code* (not docs) was not inspected.
- The **installed artifact is 1.1.0**, so behavioral verification of the *current* binary is 1.1.x-local; the pin stated in repo docs (1.0.0) describes the state at the 2026-10-04 probe.
- **LLM-side caution:** one year lies between these releases; treat any repo-doc URL that does not carry a version as floating.
- `llama-server` runs **unsandboxed by convention** (calibration doc, line 152); not independently re-evaluated here.
- Pi's claim surfaces are docs, not a security contract: its own `security.md` states that "expected local-agent behavior, prompt injection from untrusted content, lack of a built-in sandbox" are outside its security boundary — the Vermittler must not assume pi defends komki.

## Sources

- Local: `apps/komki_cli/lib/komki_cli/{pi,profile,config,steps}.ex`; `apps/komki_policy` test suite; `docs/rfcs/0003-vertrauliche-ki-arbeitsraeume.md`; `docs/research/2026-10-13-agent-policy-models-openappa-pace.md`; `docs/research/2026-10-04-probe-harness-sandbox.md`; installed artifact `/Users/crn/.asdf/installs/nodejs/24.11.1/lib/node_modules/@earendil-works/pi-coding-agent` (package.json, CHANGELOG.md) — all inspected 2026-10-14.
- External (fetched 2026-10-14): `raw.githubusercontent.com/earendil-works/pi/v1.0.0/packages/coding-agent/docs/{cli,mcp,extensions}.md`; `github.com/earendil-works/pi` (canonical repo, observed redirect from `badlogic/pi-mono`).
