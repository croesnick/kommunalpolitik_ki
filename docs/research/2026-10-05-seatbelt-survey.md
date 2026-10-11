# Seatbelt-Survey: Wie andere AI-Harnesses auf macOS sandboxen

Stand: 05.10.2026 (Recherche aus Anlass der Session-Crash-Analyse; alle
Quellen am Abrufdatum geprüft). Bezieht sich auf das `komki`-Profil
(deny-default, Port-Only-Netz, isoliertes HOME — siehe `apps/komki_cli`).

## Branchenübersicht

Alle großen AI-Agent-Harnesses sandboxen auf macOS über denselben
Mechanismus, den wir nutzen: `sandbox-exec`/Seatbelt mit deny-default.
App Sandbox (Entitlements), Container oder VMs spielen für CLI-Agenten
keine Primärrolle (VMs nur als Ausweichpfad, z.B. Osaurus auf macOS 26+).

| Lösung | Mechanik | Bemerkenswertes |
|---|---|---|
| Claude Code | dynamische SBPL-Profile pro Bash-Aufruf via `sandbox-exec -p`, Netz nur über lokalen Proxy-Port; Generator öffentlich: [anthropic-experimental/sandbox-runtime](https://github.com/anthropic-experimental/sandbox-runtime) | Regelvorlage nennt sich selbst „inspired by Chrome sandbox policy" |
| OpenAI Codex | dynamische Profile aus Rust ([seatbelt.rs](https://github.com/openai/codex/blob/main/codex-rs/sandboxing/src/seatbelt.rs)); write-scopes per Parameter | Schützt Schreib-Ahnen zusätzlich per `file-write-unlink`-Denies (rename-Bypass) |
| Goose (Block) | sandboxt den *ganzen* Agent-Prozessbaum, Netz via CONNECT-Proxy | Alles-oder-nichts-Ansatz |
| OpenCode | experimentell, opt-in (macOS), Presets; `bash:unsandboxed`-Retry mit Permission-Flow | MCP-Server ausgenommen |
| Cursor | dynamische Profile, protected paths (`.git/config`, Settings) | Konfig-Merge admin > repo > user |
| Termic | Monitoring-Modus: erst aufzeichnen, dann enforce | Bestes Muster für Allowlist-Aufbau |
| Bazel darwin-sandbox | `sandbox-exec -f` pro Build-Aktion | Vorbild für Boot-Gate-Disziplin; sporadische sandbox-exec-Crashes auf macOS 26 dokumentiert ([bazel #30535](https://github.com/bazelbuild/bazel/issues/30535)) |

## Übernommen: die TUI/Terminal-Klasse

Unser Profil entstand aus Headless-Sonden — die Regeln, die eine TUI auf
einer Pty braucht, fehlten schlicht, weil sie headless nie gebraucht
werden. Die folgende Klasse (Muster aus [macos-sandbox-utils.ts](https://github.com/anthropic-ai/sandbox-runtime/blob/main/src/sandbox/macos-sandbox-utils.ts)
im sandbox-runtime; Terminal-Ioctl-Problem: [srt #419](https://github.com/anthropic-experimental/sandbox-runtime/issues/419))
ist seit dem 05.10.2026 Teil von `KomkiCli.Profile`:

```
(allow file-ioctl (literal "/dev/tty"))
(allow file-ioctl (regex #"^/dev/ttys[0-9]+$"))
(allow pseudo-tty)
(allow process-info* (target same-sandbox))   ; nur innerhalb des eigenen Sandkastens
(allow signal (target same-sandbox))
(allow mach-priv-task-port (target same-sandbox))
(allow user-preference-read)
(allow distributed-notification-post)
(allow ipc-posix-sem)
(allow sysctl-read (sysctl-name-prefix "hw."))       ; versionsfest: neue OS-Versionen
(allow sysctl-read (sysctl-name-prefix "kern.proc.")) ; lesen neue hw.*/kern.proc.*-Felder
```

Die `hw.*`-Präfixregel ist bewusst breit: zsh 5.9 auf darwin25/26 las neue
nicht gelistete `hw.*`-Sysctls und scheiterte still ([claude-code #49820](https://github.com/anthropics/claude-code/issues/49820),
[Cursor-Forum](https://forum.cursor.com/t/sandbox-fails-to-initialize-for-zsh-on-macos-26-tahoe-darwin25-zsh-5-9-reads-unwhitelisted-hw-sysctls/161023)).

## Das Spawn-Kontext-Phänomen (macOS 26/27)

Unser Beobachtung — sandboxed node stirbt aus gewöhnlichen fork-Ketten mit
SIGABRT beim Init, ohne sichtbare Seatbelt-Denial, kontextabhängig — hat
branchenweit Geschwister, alle auf neueren macOS-Builds:

- [uv #21337](https://github.com/astral-sh/uv/issues/21337): aus Pipes
  gespawnte Prozesse → SIGABRT; interaktiv OK (macOS 26.6)
- [codex #23185](https://github.com/openai/codex/issues/23185): gleiche
  Binary, gleiche Argumente — TUI-Spawns `Sandbox(Signal(6))`, externe
  exec-Läufe OK (macOS 26.4)
- [claude-code #66735](https://github.com/anthropics/claude-code/issues/66735):
  Crash abhängig von der Spawn-API-Form (posix_spawn vs. fork)
- [bazel #30535](https://github.com/bazelbuild/bazel/issues/30535),
  [#29537](https://github.com/bazelbuild/bazel/issues/29537): sporadische
  SIGSEGV in der sandbox-exec-Schicht auf macOS 26.x

Unsere Abhilfe ist architektonisch statt pro-Denkmal: Die tmux-Pane der
Session startet das komki-Escript selbst als Mini-BEAM (`session-chain`),
der die Sandbox-Kette als Port-Kind spawnt und die Pane-PTY durchreicht
(`:nouse_stdio`). Der Headless-Lauf nutzt denselben Port-Weg ohnehin.

## sandbox-exec-Status (Deprecation)

`sandbox-exec` ist seit Jahren als deprecated markiert (man page), funktioniert
auf macOS 26/27 unverändert, und Apple nutzt es selbst massiv. Einen
offiziellen Migrationspfad für CLI-Prozesse gibt es nicht — die Anfrage ist
offen: [apple/containerization #737](https://github.com/apple/containerization/issues/737).
Konsequenz für uns: Boot-Gate vor jedem Lauf bleibt Pflicht; die
Übersiedlung in einen robusteren Mechanismus (VM via Apple Containerization)
ist ein Kandidat für spätere Ausbaustufen, nicht für den MVP (vgl. Ticket #75).

## Noch nicht übernommene Kandidaten

Geordnet nach Nutzen; alle mit Quelle im sandbox-runtime bzw. Codex:

1. **Move/Symlink-Bypass-Schutz**: `file-write-unlink`/`file-write-create`-Denies
   auf geschützten Pfaden *und deren Ahnen* (sonst `mv`-Bypass). Relevant,
   sobald `arbeit/` geschützte Dateien enthält.
2. **Eigene Konfiguration schützen**: deny auf die eigene Profil- und
   Config-Datei, damit der Sandkasteninsasse sie nicht editieren kann.
3. **Monitoring-Modus** (Termic-Muster): Profil eine Zeitlang im
   Aufzeichnungsmodus fahren, um Allowlisten datengetrieben zu erweitern —
   der bessere Weg für künftige Regelarbeit als Rätselraten.
4. **Netz via lokalem Proxy** (Anthropic-Muster): statt nur einem Port
   einen kontrollierenden HTTP-Proxy vorschalten, wenn je Remote-Zugänge
   für autorisierte Quellen dazukommen (nicht für den KomKI-CLI-MVP).

## Quellen

Abrufdatum aller Links: 05.10.2026. Kernaufstellung im Kapitel „Branchenübersicht";
Einzelnachweise an den jeweiligen Stellen. Vollständige Recherche (incl.
Sekundärquellen zu Warp, Osaurus, safehouse u.a.) im Session-Protokoll
vom 05.10.2026.
