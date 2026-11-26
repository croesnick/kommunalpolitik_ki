## 0.1.1 (2026-11-26)

### Fixes

#### Mach-O load commands yield only validated read scopes

A Mach-O binary names the dylibs it wants, and `Seatbelt.MachODeps.dylib_dirs/1`
turned every one of those load commands into a `file-read*` scope for the
sandbox profile — unchecked. A binary that declares a root-level dependency
such as `/libfoo.dylib` widened its own sandbox to
`(allow file-read* (subpath "/"))`: read access to every file the user can
read, from a process whose confinement is the whole point of the profile
(audit #467, finding F2; ticket #474).

The walk now validates every directory before granting it: the declared
dependency must resolve to an existing file (a dead install name, like the CI
build path a precompiled NIF carries, holds nothing dyld could load), both
path forms of its directory — the linked form and the kernel-canonical one —
must sit inside an allowlist of roots (package managers and the system:
`/opt/homebrew`, `/usr/local`, `/usr/lib`, `/System/Library`; plus the install
prefix of the program, its own directory and the parent for the conventional
`<prefix>/bin` layout), and breadth ceilings are refused — never `/`, and
nothing shallower than two segments. A declaration that fails yields no scope
and is not walked further; the worst case is a profile that is too narrow,
never one that is too wide.

Callers that know their install tree better than the walk can derive it pass
their roots explicitly with the new `dylib_dirs/2`. The default prefix is
location trust: a binary planted next to user secrets (for example a
PATH-shadowed `llama-server`) keeps that lever until callers adopt the
parameter — komki tracks that follow-up in #474.
