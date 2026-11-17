## 0.2.0 (2026-11-17)

### Brüche und große Neuerungen

#### /sitzungsmappe findet die Sitzung im RIS und liest die ganze Tagesordnung

`/sitzungsmappe 17.11.` sucht jetzt zuerst die Sitzung an diesem Tag, holt ihre öffentliche Tagesordnung, liest jeden Tagesordnungspunkt und sucht frühere Beratungen im RIS und passende Notizen im Vault. Die Mappe hat je Punkt einen Abschnitt „Vorgeschichte“ und belegt RIS-Aussagen mit Link und Abrufdatum. Gibt es an dem Tag keine oder mehrere Sitzungen, fragt pi nach. Dafür kennt pi zwei neue Werkzeuge: `ris_sessions` listet Sitzungen eines Zeitraums mit Uhrzeit und Gremium, `ris_agenda` liefert die öffentlichen Tagesordnungspunkte einer Sitzung. Nicht-öffentliche Punkte liefert komki weiterhin nicht. pi kennt jetzt das heutige Datum und rät bei einem Datum ohne Jahr keins mehr.

### Fehlerbehebungen

#### Abgelehnte Offenlegung wird nicht mehr als Freigabe übermittelt

Bei einer Offenlegungsfreigabe konnte die Teile-Auswahl ohne das abschließende GO
als Freigabe geschrieben werden: Wer nach der Auswahl mit „n" antwortete oder die
Eingabe endete, dessen gewählte Teile wurden trotzdem dem Vorstand offengelegt —
die CLI meldete dabei „0 von 1 Anfragen freigegeben". Ohne Terminal (Skript, Pipe)
wurde die Offenlegung sogar automatisch für alle Teile erteilt. Eine Ablehnung
schreibt jetzt immer eine Absage (go:false); headless gibt es keine Offenlegung —
wie bei allen GO-Entscheidungen bleibt sie der Person am Terminal vorbehalten.

#### PDF-Lesung läuft in einem eigenen Hilfsprozess

Der Dokument-Connector liest PDFs nicht mehr in seinem eigenen VM: Ein
zweiter Betriebssystemprozess — derselbe BEAM, dasselbe Seatbelt-Profil —
lädt das PDFium-NIF. Stirbt der Hilfsprozess durch einen Crash, durch
Speicherdruck oder wenn er das Zeitbudget von 12 Sekunden überschreitet,
antwortet der Connector genau diesen einen Aufruf mit `upstream-error` und
bleibt erreichbar. Vorher konnte eine einzige präparierte PDF-Datei (stark
expandierender Datenstrom) den Connector für die ganze Instanz blockieren
oder komplettlegen — nachgemessen: 1,8 MB Datei, 54 Sekunden Rechenzeit und
rund 32 GB Speicherbedarf in einer einzigen Anfrage.

Die Adresse-Raum-Begrenzung bleibt bewusst nur ein Versuch in der Aufrufzeile:
macOS weist `setrlimit` für RLIMIT_AS systemweit ab (gemessen), wirksam sind
hier Zeitbudget und Crash-Isolation. Eine Dekompressionsgrenze vor der
Materialisierung gehört in das externe Paket ex_pdfium und bleibt offen
(Ticket #488).

#### Sitzungen mit pi ab 1.5.1 starten wieder

pi folgt seit Version 1.5.1 beim Laden von Extensions dem echten Pfad von
Symlinks. Bei global per pnpm installiertem pi landen diese Zugriffe im
pnpm-Store-Spiegel, den das Seatbelt-Profil nicht freigab — die Sitzung
wäre ab pi 1.5.1 beim Laden der Anzeige sofort beendet. Das Profil gibt
die Spiegel-Ziele der Abhängigkeits-Symlinks jetzt frei.

#### RIS: TOP-Texte ohne rohe HTML-Entities

`ris show` lieferte Textblöcke mit rohen Entities wie `W&uuml;rdigung`, `&sect; 246e BauGB`
oder `&bdquo;Gesetz …&ldquo;`, wenn das RIS mehr als die XML-Kern-Entities ausspielt — das
kostete Tokens und ließ Zitate vom Original abweichen (Quellenpflicht). Der Connector
dekodiert jetzt den Latin-1-Vorrat von HTML 4 und die Satz- und Währungszeichen deutscher
Gremientexte (Anführungszeichen, Gedankenstriche, Euro); unbekannte Entities bleiben roh
stehen. Neu dazu: `priv/ris_tagesordnung.exs` prüft die Tagesordnung eines Sitzungstags
gegen das echte RIS (eine Freigabe per Touch ID) und meldet „Texte mit ungelösten
HTML-Entities: N“.

#### Terminal-Ausgaben aus Log- und Dateidaten ohne Steuersequenzen

Der Denial-Footer (`komki run --capture-denials`), der Aufnahme-Header von
`komki session` und Fehlergründe mit Pfadangaben (etwa `--gguf-from`)
filtern jetzt Terminal-Steuersequenzen aus Daten von Dateisystem und
Unified Log heraus: OSC-52-Sequenzen können die Zwischenablage nicht mehr
schreiben, CSI-Folgen keine Zeilen mehr überschreiben. Datei- und Pfadnamen
bleiben lesbar; ein eingebetteter Zeilenumbruch in einem Dateinamen wird
sichtbar als `\n` gezeigt, statt eine zusätzliche Aufnahme-Zeile
vorzutäuschen.

#### komki-tresor läuft nur mit passendem Programmpin

`komki secret set`, `komki secret erzeugen` und der Geheimnis-Schritt von `komki setup` führen `komki-tresor` jetzt nur aus, wenn der festgehaltene Programmpin passt — dasselbe Urteil wie der Doctor-Pin beim Start (`komki up`), gesprochen vor dem Start des Programms. Ein ausgetauschtes oder gepflanztes `komki-tresor` kann keine frischen Geheimnisse mehr versiegeln und keine Siegel mehr öffnen; komki verweigert vorher mit der Meldung des Doctor-Pins (etwa „verändert seit dem Festhalten … ‚komki setup‘ (fragt nach)“) und speichert nichts. Nach einem gewollten Update wie bisher `komki setup` ausführen und die Rückfrage bestätigen.

#### komki-policy verify verwirft weitere geschmiedete Beweise

Drei Klassen geschmiedeter Permit-Bäume, die `komki-policy verify` (und die Bibliotheksprüfung `KomkiPolicy.Verify.check/4`) fälschlich als gültig bescheinigt hat, werden jetzt verworfen:

- Eine `binding_condition`-Prämisse mit `"expression": null` kann eine fehlende Operationsregel nicht mehr kaschieren: Die Eingabevalidierung lehnt `null` als Ausdruck ab (Eingabefehler, Exit 2), und ohne Registry-Eintrag feuert `expression_mismatch` immer — unabhängig vom behaupteten Wert.
- Eine Fakt-Prämisse entlädt ihren Slot nur noch mit der Tatsache, die ihr Name benennt (`fact == name`); eine auf eine andere, wahre Tatsache umgelenkte Prämisse ist eine unbekannte Prämisse (Exit 1).
- Ein Permit-Baum, dessen nachgerechnete Prämisse nicht `true` ergibt — Basisfakt, Vertragsfeld `workspace.valid` oder Objektprüfung —, wird mit dem neuen Befund `premise_not_true` verworfen; der behauptete Wert der `not_quarantine`-Prämisse wird gegen die nachgerechnete Klassifikation verglichen, statt ignoriert zu werden.

Der Befund `fact_value_mismatch` bei `workspace_contract_valid` benennt jetzt die Tatsache im `fact`-Feld (vorher `null`).

#### Vermittler: Argumentgrenzen vor der Kanonisierung; Session-Angabe im Journal als behauptet

Ein `tools/call` mit tief verschachtelten Argumenten konnte den Vermittler
lahmlegen: Die Parameter-Vorprüfung band abgelehnte Aufrufe per kanonischem
Hash, und der kanonische Encoder rückt pro Ebene ein — rund 150 KB Anfrage
mit ~20 000 Verschachtelungsebenen trieben dabei Gigabytes an Allokation
(Θ(Tiefe²)). Die Vorprüfung begrenzt Tiefe (32 Ebenen) und Gesamtgröße
(256 KB Gewicht) der rohen Argumente jetzt vor der Schema-Prüfung und vor
dem Journal-Eintrag; übergroße Aufrufe werden billig und strukturiert
abgelehnt, der Hash bindet sie bis zur Grenze. Der Encoder selbst bekommt
eine explizite Tiefengrenze von 128 Ebenen mit strukturiertem Fehler.

Außerdem führt das Entscheidungs-Journal die `X-Komki-Session`-Angabe
nicht mehr als Sitzungsidentität, sondern als das, was sie ist: eine
unbelegte Behauptung des Aufrufers. Jeder Datensatz markiert die
Zuordnung seit `komki-pdr/6` mit `session_id_provenance: "caller-asserted"`;
eine spätere Journal-Auswertung schreibt Anrufe nicht mehr ungeprüft der
behaupteten Session zu.

#### Websuche: feindliche Treffer binden den Connector nicht mehr

Suchergebnisse von Brave sind Fernsteuerung: Titel und Beschreibung eines Treffers
stehen auf fremden Seiten. Schickt die Suchmaschine einen überlangen '<'-Run als
Titel zurück, arbeitete der Connector die ganze Zeichenkette ab — am 2-MiB-Limit
der Antwort bis 62 ms pro Treffer, auf Regex-Engines ohne Bumpalong-Terminierung
(Sicherheits-Audit #467, Fund F11) Minuten bis Stunden. Jetzt wird jede
ferngesteuerte Eingabe vor der Bereinigung hart auf 8 KiB gekappt und der
Tag-Strip läuft als linearer Scan statt über einen Backtracking-Regex: Die
Bereinigung bleibt konstant schnell, egal was die Gegenseite schickt. Was hinter
mehr als 8 KiB Rohdaten liegt, wird nicht mehr rekonstruiert — Titel und
Beschreibungen enden ohnehin bei 300/1000 Zeichen, der Unterschied ist unsichtbar.
