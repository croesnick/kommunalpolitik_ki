# Seatbelt-Profile für Escripts: Connectoren, Egress, Vermittler (Ticket #146, #137)

Stand: 2026-10-23/24, macOS 27.2 (Build 26B5101f), Erlang/OTP 28.3.1 (asdf), Elixir 1.19.5.
Ergebnis: `KomkiCli.EscriptProfile` (gemeinsame Grundschicht), `KomkiCli.ConnectorProfile`
(Connectoren, Egress), `KomkiCli.MediatorProfile` (Vermittler).

## Methode

Je Runde ein Profil schreiben, eine Erlang-Sonde darunter starten und die Denials aus dem
Unified Log lesen:

```sh
cd /
/usr/bin/env -i HOME=<base>/run PATH=/usr/bin:/bin \
  /usr/bin/sandbox-exec -f <profil> <erlang-root>/bin/escript <sonde> <op> <args> \
  > out.log 2>&1 < /dev/null
/usr/bin/log show --start "<startzeit>" --predicate 'sender == "Sandbox"' --style compact \
  | grep -E 'Sandbox: (escript|beam|erl|sh|bash|dirname|basename|erlexec|inet_gethost|erl_child_setup|security)'
```

Sonde: `apps/komki_cli/test/fixtures/probe.escript` (Quelltext-Escript; Operationen `read`,
`write`, `list`, `connect`, `connect-unix`, `bind-unix`, `nop`). Als Stellvertreter für
„ein gebautes Escript mit Elixir“ diente `komki-mediator` (`mix escript.build`), später die
echten Escripts aus `komki-connectors` (egress, ris, web, vault, mediator).

Start immer über den aufgelösten `escript`-Pfad, nicht über den Shebang: `#!/usr/bin/env
escript` landet im asdf-Shim (Shell-Skript), der unter der Sandbox scheitert (gleiche Klasse
wie der node-Shim, Ticket #70).

## Runden (Grundschicht)

| Runde | Profil | Ergebnis | Folge |
|---|---|---|---|
| 0 | exec/read Erlang-Wurzel, /bin/sh, dirname/basename | rc=134 (SIGABRT), keine Denials | Boot-Schicht fehlt |
| 1 | + Boot-Schicht aus Ticket #70/#100 | `Failed to exec /bin/bash as variant for /bin/sh`; Denials `/private/var/select/sh`, `process-exec* /bin/bash`, sysctl `kern.osproductversion`, `kern.osvariant_status`, `kern.bootargs`, `kern.iossupportversion`, `hw.ephemeral_storage` | /bin/sh ist ein Variantenwähler |
| 2 | + select/sh, /bin/bash, Sysctls | `getcwd: Operation not permitted`, `erl: Cannot determine real path to erl`; Denials `file-read-metadata /`, Vorfahren der Erlang-Wurzel, `kern.ngroups`, `kern.hostname` | cwd `/`, Metadaten der Vorfahren (dyn_erl `--realpath`) |
| 3 | + Metadaten, cwd `/`, `env -i` | `erts_mmap: Invalid sys_page_size`; Denials `hw.pagesize_compat`, `hw.ncpu`, `hw.machine`, `kern.osrelease`, `kern.ostype`, `kern.version`, `/etc`, opendirectoryd | BEAM-Sonden |
| 4 | + BEAM-Sonden | **rc=0**. Folgenlose Rest-Denials: Zeitzone (112×), `hw.optional.*`, `machdep.cpu.*`, `/private/etc/protocols`, `/dev/fd` (erl_child_setup), notification_center-shm | `hw.`/`machdep.cpu.`-Präfix, Zeitzone, protocols, /dev/fd erlaubt |
| 5 | Grundschicht + Escript-Datei | `komki-mediator --help` rc=0 nach Lese-Regel für die Escript-Datei | — |
| 6 | Tunnel-Probe mit `:ssl` | `dlopen … libcrypto.3.dylib (blocked by sandbox)`; Denial `file-read-metadata /opt/homebrew/opt/openssl@3` | crypto-NIF linkt Homebrew-OpenSSL über einen Symlink-Pfad: dylib-Verzeichnisse (otool-Walk, `KomkiCli.MachODeps`) plus Metadaten der Vorfahren |

Bewusst verweigert (folgenlos): `network-outbound /private/var/run/syslog` (os_log-Fallback),
`~/.CFUserTextEncoding`, `/dev/tty`, `mach-lookup com.apple.logd`, `network-bind local:*:0`
(BEAM beim Start), `/opt/homebrew/etc/openssl@3/openssl.cnf`, `inet_gethost` `signal children`
(außer im Egress) und `system-info net.link.addr`.

## Socket, Netz, Dateisystem

| Prüfung | Profil | Ergebnis |
|---|---|---|
| `bind-unix <base>/run/connectors/vault.sock` + chmod 0600 | connector-vault | ok mit `network-bind (local unix-socket (path-literal …))` und `file-read* file-write* (literal …)` |
| Schreiben auf geerbtes stdout/stderr (Log-Redirect der Spawn-Shell) | alle | ok ohne Regel (nur Metadaten-Denial); Log-Regel trotzdem drin |
| `connect 127.0.0.1 49532` | connector-web | ok (`remote tcp "localhost:49532"`) |
| `connect 127.0.0.1 49531` | connector-web | `eperm`, Denial `network-outbound remote:*:49531` |
| `connect 93.184.215.14 443` | connector-* | `eperm`, Denial `remote:*:443` |
| `connect example.com 443` | connector-* | `nxdomain`; Denials `inet_gethost` auf `/private/var/run/mDNSResponder`, `/private/etc/hosts`, `net.routetable.0.0.3.0` (kein DNS) |
| DNS im Egress | egress | ok mit mDNSResponder-Socket, `/private/etc/hosts`, `net.routetable.0.0.3.0`, `signal (target children)` |
| `CONNECT api.search.brave.com:443` + TLS 1.3 (Sonde unter connector-web, Egress unter egress.sb) | beide | ok: `{protocol,'tlsv1.3'}`; Egress-Log `decision: allow`, Adresse 3.33.153.106 |
| `CONNECT example.com:443` | beide | Egress antwortet 403, Log `not_allowed` |
| `list ~/.ssh`, `read ~/.zshrc` | connector-vault | `eperm` |
| Schreiben `vault/komki-test/n.md` / `vault/outside.md` | connector-vault | ok / `eperm` (`file-write-create`) |
| `connect 127.0.0.1 4010` (RIS-Mock) | connector-ris mit `ris_mock_port` | ok; Port 49531 verweigert |

## TLS-Wurzeln (offener Punkt für die Connector-Lanes)

`:public_key.cacerts_get/0` startet auf macOS `/usr/bin/security export … SystemRootCertificates.keychain`.
Unter dem Connector-Profil: `{failed_load_cacerts, eopnotsupp}`. Mit erlaubtem exec von
`security` verlangt das Werkzeug zusätzlich `mach-lookup com.apple.SecurityServer`,
Nutzer-Preferences und `systemkeychaincheck.socket`. SecurityServer würde dem Connector den
Schlüsselbund öffnen, auch den Brave-Key. **Nicht erlaubt.** Das Profil gibt stattdessen
`/private/etc/ssl/cert.pem` frei; `:public_key.cacerts_load("/etc/ssl/cert.pem")` liefert 128
Wurzeln, und der TLS-1.3-Tunnel zu Brave läuft damit (siehe oben). RIS- und Web-Connector
nutzen heute `cacerts_get/0` und scheitern unter dem Profil mit `internal`. Die Umstellung auf
`cacerts_load/1` gehört in die Connector-Lanes beziehungsweise zum Integrator.

## Vermittler

Mit dem echten `komki-mediator` (Branch `komki-connectors`) unter `mediator.sb`, frische Basis:
Erstprovisionierung (registry.json, room.json, documents), Journal mit `uappnd`
(`/usr/bin/chflags` unter dem Profil), healthz und MCP über `<base>/run/mediator.sock` mit
Bearer-Token, `vault_search` über den Connector-Socket ok (`decision: permit`), `web_search`
ohne Key ergibt `credential-missing`. Restliche Denials: `openssl.cnf` (folgenlos).

## Live-Lauf in einer Wegwerf-Basis

`KOMKI_HOME=/private/tmp/kup`, `komki init --port 59996 --ris-mock-port 4010`, die fünf Escripts
in `<base>/bin`. Die Kette von `komki up` ab Egress (Connectors.up, Mediator.up; llama bewusst
nicht, um die echte Instanz und ihren llama nicht zu belasten), dann `komki status` (alle fünf
Prozesse `running`), `komki doctor` (alles ok, Ping je Connector mit Fassung, Profile
byte-stabil, Journal `uappnd`), `komki down` zweimal (idempotent). Der Schlüsselbund kam aus
einem Fake-Kommando. Der Dummy-Key stand nicht in `ps eww` des Web-Connectors. Der Connector
meldete nicht `credential-missing`, sondern scheiterte erst an `cacerts_get/0` (siehe oben).
Damit ist der stdin-Weg belegt.

## Automatisierte Proben

`apps/komki_cli/test/komki_cli/sandbox_profile_test.exs` (`@tag :sandbox`, nur macOS mit
sandbox-exec und escript): Positivkontrolle je Profil, Canary-Datei im Home und `~/.ssh`
verweigert, `connect example.com:443` und `93.184.215.14:443` aus Connector- und
Vermittler-Profil verweigert, Vermittler ohne Outbound zu Loopback-Ports, Vermittler verbindet
nur Connector-Sockets, Connector bindet nur den eigenen Socket, Vault schreibt nur in
`komki-test`.
