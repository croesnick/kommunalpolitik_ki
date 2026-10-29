# seatbelt

A small, dependency-free Elixir library for running programs under macOS
Seatbelt confinement (`sandbox-exec`) with deny-default profiles — with the
pieces that usually cost a weekend of denial-log archaeology already in place:

- **Deterministic profile generation** — `Seatbelt.SBPL` rule emitters and
  `Seatbelt.Preset` validated rule layers. Fixed inputs produce
  byte-identical profile text, which makes profile identity checkable:
  regenerate and byte-compare to detect drift.
- **Escript/BEAM runtime layer** — `Seatbelt.Escript`: the rule set that lets
  a sandboxed Escript boot (escript → erl → erlexec → beam.smp chain, crypto
  NIF dylibs, Burrito single-file wrappers). Sandboxed Escripts under
  Seatbelt are a recurring, poorly documented problem; this layer is
  denial-log validated (macOS 27.2).
- **Boot gate** — `Seatbelt.BootCheck`: run a probe under the generated
  profile via `sandbox-exec` before every real start. `sandbox-exec` has a
  documented instability class on recent macOS builds; the boot gate is the
  positive control.
- **Program pins** — `Seatbelt.Pins`: SHA-256 of entry programs and whole
  package trees, plus new/changed drift classification. Profiles only pin
  *paths*; pins make the bytes at those paths part of the checked state.
- **Host path helpers** — `Seatbelt.canonical/1` (kernel view of a path;
  under macOS `/tmp` → `/private/tmp`) and `Seatbelt.erlang_root/1`.

## Guarantees

- Profiles are built on `(deny default)`; the emitters never produce
  `(allow default)`.
- Kernel-canonical paths only: the caller resolves every path with
  `Seatbelt.canonical/1` before it enters a profile (Seatbelt rules in
  symlink form do not match).
- No injection through inputs: every caller-supplied string passes
  `Seatbelt.SBPL.quote!/1`, which raises on `"`, `\` and control
  characters, and header comments must not contain line breaks. A path can
  never close its literal and smuggle in a rule.
- Fixed inputs → byte-identical output, enforced by goldens and determinism
  tests.
- All emitted profile text — comments included — is ASCII/English. Comment
  lines are part of the byte-identity contract: changing them changes the
  profile identity of every consumer.

## Two boot layers, deliberately

`Seatbelt.Preset.macos_exec_boot/0` and `Seatbelt.Preset.escript_boot/0`
are two independently validated layers from different denial-log campaigns,
not duplicates. The escript layer additionally needs the
`/System/Volumes/Data` metadata read, a `/dev/null` write and the system
house read subpaths. Do not merge them without a fresh validation run.

## Linux behavior

The library stays generatable on hosts without macOS tooling: the otool walk
returns `[]` without `otool` (or for unreadable binaries) and tests that need
`sandbox-exec`/`otool` skip themselves. Confinement itself is macOS-only —
on Linux the library degrades to profile *generation*, not enforcement.

## Consumers

This library grew out of the komki CLI (Ticket #226); komki's concrete
profiles (pi session, llama-server, Erlang escript roles) are compositions
over it and live in the komki app. The library itself knows nothing about
komki and has zero runtime dependencies.

## Status

v0.1.0 — in-repo library, API not yet frozen. `Seatbelt` profiles depend on
undocumented SBPL behavior (`sandbox-exec` is marked deprecated by Apple,
works unchanged on macOS 26/27, and is what every major AI-agent harness
uses on macOS today); every rule here cites the campaign that validated it.
