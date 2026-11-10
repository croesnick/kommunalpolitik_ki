# Was nur mit echter Hardware geht

> **Zweck:** die eine Liste der komki-Pfade, die die Mock-Welt nicht
> nachstellen kann. Mock-Welt heißt: Statt externer Systeme wie RIS und
> Websuche laufen lokale Übungs-Gegenstellen aus `apps/komki_mock`, statt
> Secure Enclave und Schlüsselbund ein Test-Ersatz ohne Rückfrage. Nicht
> nachstellbar sind Pfade, die echte Hardware oder Rechte des Betriebssystems
> brauchen. Für jeden Pfad steht hier, was die automatischen Tests stattdessen
> prüfen und wie der echte Pfad vor einem Release geprüft wird. Grundlage ist
> die Karte „Mock-Welt: komki autonom durchtesten“ (Ticket #347, Ticket #337).

Alles andere soll ohne Mensch am Rechner durchlaufen, in `mix test` ebenso
wie in Agents, die die echten Programme starten. Kommt ein Pfad hinzu, der
nur mit echter Hardware geht, gehört er in diese Liste.

| Pfad | Warum nicht nachstellbar | Was die automatischen Tests stattdessen nutzen | Echte Prüfung |
|---|---|---|---|
| Secure Enclave und Touch ID (`komki-tresor`) | Das Öffnen eines Siegels braucht die Secure Enclave dieses Macs und die Freigabe durch einen Menschen. | Ein Test-Tresor (`apps/komki_cli/test/support/fake_tresor.exs`) spricht das Protokoll von `komki-tresor` mit echter Schlüsselvereinbarung, aber ohne Secure Enclave und ohne Rückfrage. Den Schlüsselbund ersetzt `/usr/bin/false`. | Live-Test, siehe unten |
| Homebrew-Installation (`make komki-tap`) | Homebrew schreibt nach `/opt/homebrew` und ersetzt eine schon installierte Fassung. macOS prüft heruntergeladene Dateien mit Gatekeeper. komki ist nur ad hoc signiert, nicht notarisiert ([ADR 0001](adr/0001-ad-hoc-signierung-statt-developer-id.md)). | Keine Installation. Tests prüfen nur die Pfade, die die Sandbox-Profile für eine Homebrew-Installation erzeugen, nicht den Inhalt des Pakets. | Lokaler Tap nach [release.md](release.md) § Weg 2, beim Release zusätzlich der Zweit-Maschinen-Check |
| Einzeldatei-Bau mit Burrito (`make komki-burrito`) | Der Bau braucht zig 0.16.0 und xz und dauert lange. Die Einzeldatei entpackt sich beim ersten Start in das Benutzerverzeichnis. | `BurritoLaunchTest` prüft Startzeilen und Sandbox-Profile für den Burrito-Betrieb, ohne zu bauen. | Bau und Smoke-Matrix nach [release.md](release.md) |

## Live-Test für Touch ID

Der Test versiegelt einen zufälligen Testwert mit dem echten `komki-tresor`
aus `apps/komki_cli/priv` (nie mit einem aus dem `PATH`) und öffnet ihn wieder. Das Versiegeln fragt nicht, das Öffnen fragt einmal
nach Touch ID oder dem Passwort des Macs. Ein grüner Lauf zeigt also genau
eine Rückfrage, mit dem Text „komki Live-Gegenprobe: Test-Siegel öffnen“. In
den Schlüsselbund schreibt der Test nichts.

```bash
cd apps/komki_cli
mix compile                 # baut priv/komki-tresor (braucht swiftc)
mix test --include touch_id
```

Der Test (`apps/komki_cli/test/komki_cli/tresor_live_test.exs`) ist mit
`@moduletag :touch_id` markiert und in `test_helper.exs` ausgeschlossen. Ohne
`--include touch_id` läuft er nicht, und es erscheint keine Rückfrage. Auf CI läuft er nie, dort gibt es
keine Touch ID.

## Nicht auf dieser Liste

Zwei Testgruppen hängen ebenfalls vom Rechner ab, brauchen aber keinen
Menschen:

- `:sandbox` prüft die Sandbox-Profile mit `sandbox-exec`. Auf einem Mac mit
  Erlang laufen diese Tests automatisch mit, auf Linux fallen sie weg.
- `:llama_boot` startet einen echten llama-server mit dem Modell (rund 17 GB).
  Die Tests laufen nur mit `mix test --include llama_boot`, weil sie lange
  dauern, nicht weil sie eine Rückfrage auslösen.
