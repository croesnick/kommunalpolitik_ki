# komki einfacher in Betrieb nehmen: Analyse und Vorschläge

Stand: 24.10.2026. Anlass: Die Seite [In Betrieb nehmen](https://croesnick.github.io/kommunalpolitik_ki/komki/in-betrieb-nehmen/) braucht elf Schritte, darunter eine Bauschleife über sechs Apps, Kopierbefehle in ein `bin/`-Verzeichnis und eine Hand-Migration alter Konfigurationsdateien. Dieses Dokument trennt, was davon wesentlich ist und was nur zufällig entstanden ist, und schlägt einen Weg zu drei Befehlen vor.

## 1. Kurzantwort

Von den elf Schritten sind zwei wesentlich: das Modell einmal beschaffen und den Brave-Key einmal hinterlegen. Alles andere ist Verpackung, die komki selbst übernehmen kann.

Zielbild für eine Person mit Mac:

```sh
brew install croesnick/komki/komki     # komki samt llama.cpp, tmux, node und pi
komki setup                            # prüft, lädt das Modell, fragt den Brave-Key, legt die Instanz an
komki run "…"                          # oder: komki session
```

Dahin führen drei Bausteine, die sich einzeln umsetzen lassen:

1. **Ein Programm statt sechs.** Vermittler, Egress-Proxy und Connectoren werden Rollen desselben `komki`-Programms (`komki mediator`, `komki connector ris` …). Jeder Prozess läuft weiter einzeln in seiner eigenen Sandbox. Es entfällt nur das getrennte Bauen, Kopieren und Finden.
2. **`komki setup` statt Handarbeit.** Ein geführter Befehl erledigt Prüfung, Modell-Download mit Prüfsumme, Brave-Key, Vault-Wahl, Migration und Start.
3. **Homebrew-Tap als Verteilweg.** Er bringt die Fremdwerkzeuge als Abhängigkeiten mit und legt komki an einen festen Ort. Burrito bleibt als Einzeldatei für Rechner ohne Homebrew.

Favorit: zuerst Baustein 2 im bestehenden Escript-Aufbau (schneller Gewinn, kein Umbau), dann Baustein 1, dann Baustein 3. Details und Abwägungen folgen.

## 2. Ist-Aufnahme: die elf Schritte

| # | Schritt heute | Warum nötig | Art | Wie es wegfällt |
|---|---|---|---|---|
| 0 | node, pi (`npm i -g`), `llama-server` (brew), Elixir, Modell vorab installieren | komki findet Werkzeuge nur, installiert nichts | zufällig | Homebrew-Abhängigkeiten; pi als gepinnte Kopie im Paket (V3) |
| 1 | Alias auf `apps/komki_cli/komki`, Variable `B` | kein Installationsort, kein PATH-Eintrag | zufällig | Installation legt `komki` in den PATH (V3) |
| 2 | Schleife über sechs Apps mit `mix escript.build`, fünf Dateien nach `$B/bin` kopieren | jede Komponente ist ein eigenes Escript, komki sucht sie in PATH oder `$B/bin` | zufällig | ein Programm mit Rollen (V2) |
| 3 | Test-Vault von Hand kopieren | Demo-Daten liegen nur im Repo | zufällig | `komki setup --demo` legt ihn an (V1) |
| 4 | `komki init --force --vault-dir …` (30 s, kopiert 17 GB) | Instanz mit Profilen und geprüftem Modell anlegen | wesentlich, aber zu teuer | Teil von `setup`; APFS-Klon statt Kopie (V4) |
| 5 | `registry.json` und `room.json` von Hand beiseitelegen | Vorlagen werden nur angelegt, wenn keine existieren | zufällig | erkannte Alt-Vorlagen automatisch sichern und ersetzen (V1) |
| 6 | Brave-Key mit `security` prüfen oder anlegen | Schlüssel liegt im Schlüsselbund | wesentlich (einmal eingeben) | `komki setup` fragt verdeckt und legt ihn an (V1) |
| 7 | `komki up` | Prozesse starten | wesentlich | bleibt, `run` und `session` starten bei Bedarf selbst |
| 8 | `komki doctor` | Gesundheitscheck | doppelt | `up` prüft ohnehin vorab; `doctor` nur noch zur Fehlersuche |
| 9–10 | `komki run` / `komki session` | die eigentliche Arbeit | wesentlich | bleibt |
| 11 | `$B/bin/komki-mediator verify-journal --base $B`, `komki down` | Journal prüfen, stoppen | Innenleben sichtbar | `komki journal verify` (V1) |

Gemessen an Befehlen, die eine Person tippt: heute rund 25 Zeilen, davon 7 für Bauen und Kopieren. Ziel: 3.

## 3. Ursachen

- **U1 Sechs Programme mit Host-Laufzeit.** Vermittler, Egress-Proxy und drei Connectoren sind Escripts. Sie brauchen ein installiertes Erlang, das komki über `asdf which escript` sucht (`KomkiCli.Config.resolve_escript_bin/0`), weil asdf-Shims unter Seatbelt scheitern. Jedes Profil erlaubt deshalb Lesen der Erlang-Wurzel und der crypto-NIF-Bibliotheken unter Homebrew (`KomkiCli.EscriptProfile`). Wer Elixir nicht installiert hat, kommt nicht weiter, und Versionen können auseinanderlaufen (komki aus einem Stand, Vermittler aus einem anderen).
- **U2 Kein Installationsort.** komki weiß nicht, wo es selbst liegt. Deshalb Alias, `$B/bin` und die Suche „erst PATH, dann `<base>/bin`“.
- **U3 komki lädt bewusst nichts herunter.** `place_gguf` verweigert ohne `--gguf-from` („komki lädt nichts herunter“). pi kommt aus einer globalen, ungepinnten npm-Installation. Beides war als Vorsicht gemeint, verlagert die Beschaffung aber auf die Person und lässt die pi-Version offen.
- **U4 Vorlagen ohne Version.** Der Vermittler legt `registry.json` und `room.json` nur an, wenn sie fehlen (`KomkiMediator.Templates.provision!/1`). Ändert sich das Format, bleibt die Alt-Fassung liegen, und jede Anfrage wird abgelehnt.
- **U5 Geheimnisse außerhalb von komki.** Der Brave-Key wird mit `security` von Hand angelegt; komki prüft nur.
- **U6 Innenleben nach außen.** Journal-Prüfung über den Pfad des Vermittler-Escripts statt über `komki`.

## 4. Vorschläge

### V1 `komki setup` und kleine Befehle (ohne Umbau der Verpackung)

Ein geführter Befehl, der jeden Schritt prüft, bevor er ihn tut, und bei Fehlern genau sagt, was zu tun ist. Entwurf der Ausgabe:

```text
$ komki setup
Werkzeuge      ok  llama-server 0.6.0, node 24.22.1, pi 1.4.0, tmux 3.8
Modell         lädt gemma-4-26B-A4B-it-UD-Q4_K_XL.gguf (17,0 GB) …  ████████░░ 81 %
               Prüfsumme ok (ef728c8e…6e30c)
Brave-Key      nicht im Schlüsselbund. Jetzt eingeben (wird nicht angezeigt): ****
Vault          Pfad zu deinem Vault oder Enter für den Test-Vault: ⏎
Instanz        angelegt unter ~/.local/share/komki (Raum „recherche“)
Start          llama, egress, 3 Connectoren, Vermittler laufen · doctor ok
Fertig. Probier:  komki run "Was steht im RIS zum Radverkehrskonzept?"
```

Dazu:

- **Automatische Migration der Vorlagen (U4).** `registry.json` und `room.json` tragen eine Vorlagen-Version. Ist die vorhandene Datei eine *unveränderte* alte Vorlage (Hash-Vergleich gegen die bekannten Fassungen), sichert komki sie mit Datum und legt die neue an. Hat die Person sie verändert, etwa eigene Labels importiert, bricht komki ab und erklärt den Unterschied. So geht nichts Eigenes verloren.
- **`komki secret set brave`** fragt verdeckt und schreibt in den Schlüsselbund. Der Key erscheint weder im Terminal noch in einem Log; `doctor` verweist bei Fehlen genau auf diesen Befehl.
- **`komki journal verify`** statt Pfad zum Vermittler.
- **Test-Vault eingebaut:** liegt im Programm (`priv/`), `setup --demo` legt ihn an.
- **`run` und `session` starten selbst,** wenn nichts läuft. `up` bleibt für die, die es ausdrücklich wollen.

Aufwand: mittel. Nutzen: Schritte 3, 5, 6, 8 und 11 entfallen sofort, auch im heutigen Escript-Aufbau.

### V2 Ein Programm mit Rollen (Multicall)

Heute: sechs Escripts. Vorschlag: ein Release `komki`, das beim Start die Rolle aus dem ersten Argument liest.

```text
komki mediator  --base … --socket …        # bisher komki-mediator
komki egress                               # bisher komki-egress
komki connector ris --socket …             # bisher komki-connector-ris
```

Die Apps bleiben getrennt im Workspace (Unix-Prinzip, eigene Tests, eigener Vertrag). Gebündelt wird nur beim Verpacken. Das Release startet keine Anwendung von sich aus; die Rollen-Weiche startet genau den Supervisor-Baum der Rolle (`Application.ensure_all_started/1`). Ein Connector-Prozess lädt also nicht den Vermittler.

**Was sich an der Sicherheit ändert:**

- Unverändert: ein Prozess je Komponente, je eigenes Seatbelt-Profil, Schlüssel nur per stdin an den Web-Connector, Netz nur über den Egress-Proxy.
- Neu: Jedes Profil darf den Code *aller* Rollen lesen, nicht nur den eigenen. Das ist unkritisch, denn der Code ist öffentlich und enthält keine Geheimnisse. Rechte entstehen aus dem Profil, nicht aus dem Code auf der Platte.
- Besser: Alle Komponenten haben garantiert denselben Stand. Die Profile lesen eine feste Release-Wurzel statt einer per asdf gefundenen Erlang-Installation; die Suche nach `escript` und die Ausnahme für asdf-Shims entfallen.
- Zu prüfen: Die eingebettete Laufzeit muss crypto ohne Homebrew-OpenSSL laden können, sonst bleibt die dylib-Regel nötig. Der Burrito-Pilot hat die Einzeldatei ohne Host-Elixir geprüft ([Pilot-Bericht](2026-10-11-komki-burrito-pilot.md)); für die Connectoren mit TLS ist das nachzuweisen.

Aufwand: mittel bis groß (Rollen-Weiche, Profilgenerator auf Release-Wurzel umstellen, Doctor-Prüfungen anpassen). Nutzen: Schritt 2 entfällt, Elixir ist für Nutzende nicht mehr nötig.

### V3 Verteilweg: Homebrew-Tap, Burrito oder beides

| Kriterium | (a) Burrito-Einzeldatei aus GitHub-Release | (b) Homebrew-Tap mit `mix release` | (c) beides |
|---|---|---|---|
| Befehle für die Installation | Download, `xattr -d com.apple.quarantine`, `chmod`, in PATH legen | `brew install croesnick/komki/komki` | je nach Weg |
| Fremdwerkzeuge (llama.cpp, tmux, node) | weiter von Hand | als Abhängigkeiten der Formel automatisch | (b) automatisch |
| pi | weiter global per npm, ungepinnt | gepinnte Kopie im Paket (`libexec`), komki nutzt genau diese | (b) gepinnt |
| Gatekeeper | Dialog beim ersten Start (Datei ist ad-hoc signiert) | kein Dialog bei Formeln | (b) ohne Dialog |
| Pfade für Seatbelt-Profile | Laufzeit entpackt sich nach `~/Library/Application Support/.burrito/<version>`; Pfad ändert sich je Version | feste Wurzel unter `/opt/homebrew/Cellar/komki/<version>`, über `opt`-Link stabil | |
| Updates | neue Datei herunterladen | `brew upgrade` | |
| Bauaufwand | zig exakt 0.16.0 und xz auf der Bau-Maschine | Release-Tarball je Version, Formel im eigenen Tap-Repo | beides pflegen |
| Ohne Homebrew, etwa vom USB-Stick | ja | nein | ja |

Empfehlung: (b) als Hauptweg. Er löst U2, U3 (für pi) und die Fremdwerkzeuge in einem Zug, und die festen Pfade passen besser zu den byte-genau geprüften Seatbelt-Profilen als ein je Version wechselndes Entpackverzeichnis. Burrito bleibt als Einzeldatei für Rechner ohne Homebrew; der Bau existiert bereits ([Ticket #75](https://github.com/croesnick/kommunalpolitik_ki/issues/75)). Er muss nach V2 nur alle Rollen enthalten.

Nebenwirkung, die für (b) spricht: Die pi-Version wird gepinnt. Heute kann `npm i -g` jederzeit eine neue pi-Version bringen, die komki nie gesehen hat. Das ist ein Supply-Chain-Risiko an der Stelle, an der der Agent läuft.

### V4 Modell beschaffen

- **Download mit Pin (U3).** `komki setup` lädt die gepinnte Datei von Hugging Face (Quelle steht schon in `KomkiCli.Config`), mit Fortsetzen nach Abbruch und Prüfsumme vor jeder Verwendung. Vorher zeigt komki Größe, Quelle und den Hinweis auf die Gemma-Nutzungsbedingungen. `--gguf-from` bleibt für eine vorhandene Datei. Das ändert die bisherige Regel „komki lädt nichts herunter“. Die Prüfsumme sichert dabei ab, dass nur genau das gepinnte Modell genutzt wird.
- **Klon statt Kopie.** `init` kopiert heute 17 GB vom Staging-Ort in die Instanz (`File.copy` in `copy_and_verify_gguf`), also doppelter Platz und 30 Sekunden. Auf APFS legt `clonefile` (`cp -c`) eine Kopie ohne zusätzlichen Platz in Millisekunden an. Die Instanz bleibt in sich geschlossen, und das llama-Profil muss weiterhin nur den Instanzpfad lesen.

### V5 Entwicklungsschleife im Repo

Für die Arbeit am Code bleibt ein eigener, kurzer Weg, getrennt vom Weg für Nutzende:

```sh
make komki-dev     # baut das Multicall-Release (bis V2: alle Escripts), komki init --force, komki up
```

So bleibt die Seite „In Betrieb nehmen“ frei von Bauschritten.

## 5. Zielbild der Seite „In Betrieb nehmen“

1. **Installieren:** `brew install croesnick/komki/komki`
2. **Einrichten:** `komki setup` (einmalig, lädt das Modell, fragt den Brave-Key, bietet den Test-Vault an)
3. **Arbeiten:** `komki run "…"` oder `komki session`
4. **Nachvollziehen und stoppen:** `komki journal verify`, `komki down`

Alles Weitere (eigener Vault, zweiter Raum, Fehlersuche mit `komki doctor`) wandert nach „Wenn etwas hakt“.

## 6. Was bewusst bei der Person bleibt

- Den Brave-Key eingeben: Geheimnisse tippt der Mensch, komki legt sie nur ab.
- Den Nutzungsbedingungen des Modells zustimmen.
- Den Vault wählen: komki schlägt nie den echten Vault ungefragt vor.
- Das GO-Prinzip: `setup` erklärt jeden Schritt, bevor er Platz belegt oder etwas startet.

## 7. Reihenfolge und Ticket-Vorschläge

| Ticket | Inhalt | Aufwand | Abhängig von |
|---|---|---|---|
| T1 | `komki setup` (Prüfung, Brave-Key, Vault-Wahl, Start), `komki secret set`, `komki journal verify`, eingebauter Test-Vault | M | – |
| T2 | Versionierte Vorlagen mit sicherer Auto-Migration (Hash-Vergleich, Sicherung, Abbruch bei eigenen Änderungen) | S | – |
| T3 | Modell-Download mit Pin und Fortsetzen; APFS-Klon statt Kopie | S–M | – |
| T4 | Multicall-Release mit Rollen-Weiche; Profilgenerator auf Release-Wurzel; Nachweis crypto/TLS ohne Host-OpenSSL | M–L | – |
| T5 | Homebrew-Tap (eigenes Repo `homebrew-komki`), Formel mit llama.cpp, tmux, node; pi gepinnt in `libexec`; Release-Workflow | M | T4 |
| T6 | Burrito-Bau auf Multicall umstellen, Einzeldatei als Release-Anhang | S | T4 |
| T7 | Seite „In Betrieb nehmen“ auf vier Schritte umschreiben, Bauschritte in die Entwickler-Doku | S | T1, T5 |

T1 bis T3 bringen ohne Umbau den größten Teil der Erleichterung: Die Seite schrumpft schon damit von elf auf etwa sechs Schritte.

## 8. Offene Entscheidungen

1. **Download durch komki:** Darf `komki setup` das Modell selbst laden, mit Pin und Prüfsumme? Bisher galt „komki lädt nichts herunter“.
2. **Homebrew-Tap:** Ist ein eigenes Tap-Repo unter `croesnick` in Ordnung? Es wäre der erste öffentliche Verteilweg.
3. **Multicall:** Passt ein gebündeltes Programm zum Unix-Prinzip, wenn die Apps im Workspace getrennt bleiben und nur die Verpackung bündelt?
