# Durchstich 409 — „Fakt vorschlagen“ am echten Vermittler

Wegwerf-Bericht des Durchstichs (Wayfinder-Ticket
[#409](https://github.com/croesnick/kommunalpolitik_ki/issues/409), Szene 11
des Referenzszenarios). Branch `prototype/409-fakt-durchstich`, nie für main.
Gefahren am 2026-11-10: **21 Szenen geprüft, 0 rot**, Journal vollständig
verkettet (`verify-journal`: 97 Datensätze, valid). Nachfahren:

    cd apps/komki_cli && mix escript.build
    cd ../wegwerf_hub && mix escript.build
    mix run -e 'WegwerfHub.Durchstich.run()'

## Der Weg, der gefahren wurde

Kein Sprachmodell: Der geskriptete Agent (`WegwerfHub.Durchstich`) spricht
MCP über den echten Vermittler-Socket (Initialize, Session, `tools/call`),
genau wie `komki-relay.js` es für pi täte. Die Bootschrift spielt die
nutzende Person am GO (Herzschlag, `komki go`-Mechanik über die
Antwortdateien). Alle drei Prozesse laufen wie im Betrieb: Wegwerf-Instanz
(KOMKI_HOME `/tmp/kw409`), Wegwerf-Hub (Bandit auf Unix-Socket, Token nur
als Hash), ratsprojekte-Connector als Rolle des komki-Escripts. Läuft alles
unter `/tmp` — die echte Instanz bleibt unberührt.

## Die vier Fragen des Tickets

**Wie nennt Miriam das Projekt, ohne Hub-Daten in den Raum zu holen?**
`projekt_hinweis` ist freier Text, optional, ungeprüft (11.3): Der Hub
speichert ihn unverändert, die Zuordnung macht die Redaktion. Nichts am
Hub wird anhand des Hinweises verändert — die Antwort ist fix, ob das
Projekt existiert oder nicht (11.4, Zwei-Welten-Vergleich).

**Wie sieht das eine GO für ein Ergebnis mit Teilen aus?** Live aus
`komki go` (2-Teil-Vorschlag, Raum recherche):

```
Gesperrter Aufruf (Beleg pdr-…)
  Werkzeug:  rp_fakt_vorschlagen
  Aktion:    speichern — jedes Schreiben braucht dein GO
  Parameter:
    projekt_hinweis: "radweg"
    teile: [%{"aussage" => "Das Sonderprogramm Radverkehr fördert Radwege mit 60 %.", "fundstelle" => "Abschnitt 2.1", "quelle" => "web-treffer-1"}, …]
    titel: "Zwei Fakten aus der Recherche"
  Gesperrt:  missing_operation_rule
  Sichtbar für: Fraktion, Betreiber der Nextcloud (Ordner für den Stand), Sicherung (Time Machine), Vorstand
  … Existenz-Leck-Warnung …
  Ein GO gilt nur für genau diesen Aufruf, einmal, fünf Minuten lang.
```

Ein GO deckt alle Teile; das exakt gezeigte Binding ist geprüft (11.10:
fremdes GO → `release_call_mismatch`; 11.11: Replay → `release_nonce_consumed`,
Stand unverbraucht). Roughness fürs Bau-Ticket: Die Teile rendern als
Inspect-Ausdruck, nicht pro Teil — Darstellung gehört zum Freigabefenster
(#360) bzw. `komki go`.

**Welche Form hat die schmale Schnittstelle des Hubs?** Getragen und
tragfähig: Bandit-HTTP auf dem eigenen Unix-Socket (0600), genau EINE
Operation `POST /connector/fakt_vorschlagen`, Token nur als Hash (SHA-256,
konstanter Vergleich), „Hub gesperrt“ als 503, gepuffert wird nichts.
Wichtigste Formentscheidung: **Die Quittung formuliert der Connector, nicht
der Hub** — der Hub meldet nur Erfolg/Misserfolg; so ist die Antwort an den
Raum garantiert inhaltslos (kein Schlüssel, keine Kennung, keine Fortnummer)
und der Bestand nicht durch Antworten erratbar. `labels` setzt der Connector
aus `context.assigned_label`, Gate 2 prüft sie gegen die GO-Entscheidung.

**Bleibt die PDR-Spur vollständig?** Ja. `verify-journal` validiert alle 97
Datensätze; je Aufruf stehen emit/store/GO-Beleg/Vorbeleg/admit mit derselben
call_id, der Vorbeleg vor Wirkung nennt `authorized_by` beide Entscheidungen,
und bei jedem Gegenfall (11.1 bis 11.15) bleibt die Ablehnung mit vollem
Katalog im Journal, auch wo die Antwort nur den Hinweis trägt.

## Bestätigte Regeln (Szenen 11.0–11.15, 12.8/12.9, 13.4/13.6)

- **11.0** Journal-Kette `emit permitted → store not_admitted (missing_operation_rule, je Bindung eine Gegenstelle mit GO-Angebot) → store released → emit emitted → admit admitted`; Quittung `{status: vorgeschlagen, labels: B_W}`; Teile landen offen, `nicht-verifiziert`.
- **11.1/11.2** (`#417` bestätigt): kein Fenster, keine GO-Anfrage, Connector wird nie angerufen (Anfrage-Logzähler unverändert); Antwort nur `hinweis` + `recipients_outside` [fraktion, nextcloud-betreiber, sicherung, vorstand]; Journal hält den vollen Katalog ohne Aktionsfreigabe.
- **11.3/11.4** Enumeration: Antwort byte-gleich (modulo decision_id/emit_decision_id/payload_hash) gegen vollen und geleerten Hub; der Projekt-Hinweis wirkt nirgends.
- **11.5** Injizierter Text ist öffentlicher Inhalt: GO-Fenster zeigt ihn wörtlich, Hub speichert ihn roh, `nicht-verifiziert` begrenzt.
- **11.6** Ohne Herzschlag bleibt die Antwort vollständig (Katalog sichtbar), aber niemand wird gefragt — kein go_refused-PDR, kein Vollzug.
- **11.7/11.9/13.4** Geschlossenes Schema schlägt vor jeder Entscheidung zu: fehlende `quelle`, unbekannte `pruefstatus`, unbekanntes `privat` → Vorab-Fehler ohne call_id.
- **11.13a/b** Gesperrt → `hub-gesperrt`; Hub weg → `upstream-timeout`; beides: permit + `admitted: false`, Journal endet im Fehler, kein Vorschlag, kein Wiederholungsversuch.
- **11.12** Abgewählte Teile werden gelöscht; Verlauf hält nur die Anzahl fest.
- **11.14** Ohne/falsches Token: 401; unter pi-artigem Seatbelt-Profil ist der Hub-Socket unerreicht, der Vermittler-Socket erreichbar (Kontrolle).
- **11.15** Unvollständige Umgebung fällt bereits beim Erzeugen um (indeterminate, `recipients_unproven`, nie ein GO).
- **13.6** Der Hub entfernt unsichtbare Steuerzeichen aus jedem Freitextfeld.

## Korrekturen und Funds (Entscheidungen fürs Bau-Ticket)

1. **Teile brauchen einen Listentyp im Parameter-Schema.** `Sidecar.Params`
   kannte nur string/integer; „ein Ereignis mit Teilen“ braucht geschlossene
   Listen von Objekten. Im Zweig ergänzt (`:list` mit `items`), inkl.
   Fehlertexten und anubis-`embeds_many`. Der Vertrag v2 muss das festschreiben.
2. **`Gate.rendered_params` muss TIEF stringifizieren.** anubis rendert
   eingebettete Listen mit Atom-Schlüsseln — oben entpacken genügt nicht,
   die Kanonisierung des Aufrufs crasht. Im Zweig behoben; gehört in den
   echten PR.
3. **Zwei GOs im Projektraum (12.8).** `ratsprojekte@1` trägt nur `admit`:
   Ein Vorschlag aus dem Projektraum braucht heute ein emit-GO UND ein
   store-GO. Für „wie 11.0 mit GO“ (Szene 12.8) braucht die Γ-Fassung von
   `ratsprojekte@1` eine `emit`-Regel — bis dahin gilt „abgelehnt ohne
   Fenster“ (12.9) auch erst nach dem emit-Fenster. Γ-Entscheidung für
   #416/#419.
4. **`hub-gesperrt` fehlt im geschlossenen Fehlercode-Katalog** (Vertrag §3).
   Im Zweig als Vorschlag ergänzt; der ADR verlangt das Signal, der Katalog
   muss es festschreiben.
5. **11.8 bleibt opak bis B13 (#186):** Erfundene oder fremde Quellen
   durchlaufen den Weg wie 11.0; Prüfungen der Redaktion und
   `nicht-verifiziert` sind heute die einzige Grenze. Der Vermittler ergänzt
   keine URL und kein Abrufdatum.
6. **„Ausgang unklar“ (B18) ist nicht gebaut:** 11.13 schreibt heute
   `outcome: error`. Für den Timeout-Fall ist die Wirkung real unbekannt
   (der Hub könnte gespeichert haben) — B18 gehört ins Bau-Ticket.
7. **Erfolgreiche Hub-Anfragen müssen protokolliert werden** — im Wegwerf
   fehlte die 201-Zeile im Anfrage-Log, erst die Gegenprobe 11.4 deckte es
   auf. Lässt sich auf den echten Hub übertragen: Das Anfrage-Log ist der
   Beleg für connector_aufrufe = 0.
8. **11.1-Fixture:** Statt des Sitzungsmappe-Raums (nicht-öffentlicher
   Grunderwerb) trug vault-vertraulich@1 die Gegenprobe — Mechanik
   identisch (jede nicht-öffentliche Bindung bringt den Empfängertest zu
   Fall).

## Messlatte für das Bau-Ticket

- **Szenen als Tests:** Alle hier gefahrenen Zeilen (11.0–11.15, 12.8,
  12.9, 13.4, 13.6, credential-exposition) als Tests im Bau-Ticket — der
  Runner ist das Gerüst, jeder Probe benennt Szene, RFC-Anker und
  Testfamilie. Vorab-Fehler ohne call_id, Journal-Ketten je call_id,
  `verify-journal` als stärkste Einzelprüfung.
- **Mock-Welt für den Alltag:** Der Hub braucht wie RIS/Web eine Mock-Rolle
  (komki_mock) für Störfälle gesperrt/weg — hier manuell gefahren.
- **Echter Lauf als Abnahme:** Eine echte komki-Session (pi, gepinntes
  Modell), in der der Agent aus echter Recherche `rp_fakt_vorschlagen`
  aufruft und die nutzende Person das GO im Terminal gibt — als Abnahme
  des Bau-Tickets. Der Weg dorthin steht: Healthz, GO-Mechanik und
  Journal sind identisch.

## Anlagen (im Wegwerf-Bestand, nicht im Repo)

- `/tmp/kw409/` — Instanz: Journal (97 PDRs, valid), GO-Stand, Logs
- `/tmp/kw409-hub/` — Hub: Vorschläge, Verlauf, Anfrage-Log, token-hash
- `/tmp/kw409-bericht.md` — Maschineller Befunde-Bericht des Laufs
