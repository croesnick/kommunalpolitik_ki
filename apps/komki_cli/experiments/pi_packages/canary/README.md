# Seatbelt canary for the komki pi profile

Standalone experiment (not part of `run-all.mjs`). It proves what a pi
extension loaded into the real komki pi harness can and cannot do under the
generated Seatbelt profile.

## Run

```bash
node apps/komki_cli/experiments/pi_packages/canary/run-canary.mjs
```

The runner:

1. starts an OpenAI-compatible mock provider on an ephemeral loopback port,
2. loads `~/.local/share/komki/config.json`, sets only the in-memory `port`
   to the mock port, and calls `KomkiCli.Profile.generate/2` through
   `mix run`,
3. copies `canary-extension.ts` into the profile's scratch directory,
4. starts pi as `sandbox-exec -f <generated-profile> -- node <cli.js> ...`
   with `HOME` and `PI_CODING_AGENT_DIR` inside that scratch directory,
5. reads `<scratch>/canary-result.json` and writes a report next to this
   README.

The base instance profile is never written. The temporary profile and the
scratch home live under `~/.local/share/komki/tmp/canary-<timestamp>/`.

## Probes

| Probe | Expected |
|---|---|
| `fetch("https://example.com")` | denied |
| `child_process.execFile("/bin/echo")` | denied (not in exec allowlist) |
| write `/tmp/komki-canary-escape.txt` | denied |
| fetch the mock provider on the allowed loopback port | allowed |
| `process.env.KOMKI_MEDIATOR_TOKEN` | visible (residual) |
| read `<agentDir>/models.json` | visible; contains an `apiKey` (residual) |
| read `<agentDir>/auth.json` | visible (residual) |
| read `~/.local/share/komki/tmp/llama.key` | observed denied (the pi profile does not grant `base/tmp`) |

## Residual risk

The extension runs in-process with pi. Seatbelt bounds syscalls; it does not
bound data that pi already holds. An extension can read every environment
variable the harness passes (including `KOMKI_MEDIATOR_TOKEN`) and everything
in the profile's read scopes (`pi-home`, the scratch directory). In particular,
`models.json` lives in `pi-home` and contains the provider API key. The
separate `llama.key` file under `base/tmp` is outside the pi profile's read
scope, but that does not protect the key copied into `models.json`. The canary
records only booleans and error metadata, never credential values.

## Run 2026-10-24T10:27:45.913Z

- `external fetch`: `TypeError: fetch failed`, cause
  `getaddrinfo ENOTFOUND example.com` (Seatbelt blocked DNS resolution).
- `execFile("/bin/echo")`: synchronous `spawn EPERM`.
- write `/tmp/komki-canary-escape.txt`: `EPERM: operation not permitted`;
  the host confirmed the file was absent.
- mock provider: extension `GET /v1/models` returned 200 and pi completed one
  `POST /v1/chat/completions`.
- `KOMKI_MEDIATOR_TOKEN`: visible.
- `models.json`: readable and contains an `apiKey`.
- `auth.json`: readable.
- `llama.key`: not readable (profile grants `pi-home` and scratch, not
  `base/tmp`).
