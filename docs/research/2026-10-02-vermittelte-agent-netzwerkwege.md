# Vermittelte Agent-Netzwerkwege

Recherchebericht für RFC 0003. Stand und alle Quellenabfragen: 2026-10-02.

| Feld | Wert |
|---|---|
| Art | Externe Primärquellen-Recherche, keine Architekturentscheidung |
| Grenze | Keine Installation, keine echten AZ- oder RIS-Abfragen, kein Credentials-Zugriff, keine Konfigurationsänderung |
| Eigenzuständigkeit | Egress-Vermittlung und Broker-Ansätze. Sandbox-Katalog und lokale Quellcode-Analyse gehören anderen |
| Basis | RFC 0003 Rev 1, Kriterien R.3, R.4.2 bis R.4.4, R.5, R.6, R.8, R.11, B.8 |

## 1. Frage

Wie führt der Harness die Netz-Ausgaben und -Antworten eines Agentprozesses über einen Kontrollpunkt,
der außerhalb der Agentenhoheit liegt? Arbeitskontext: erste Lerniteration mit synthetischen und
ausdrücklich autorisierten öffentlichen Daten, lokale Inferenz bevorzugt, optionaler Remote-Modellweg
wählbar, OpenCode oder pi noch unentschieden, Laufzeiten sollen Netzwerkzugriff schneiden oder vermitteln.

Evidenzkennzeichnung je Befund: **Doc** = offizielle Dokumentation, mit Quellenanker. **Quelle** =
Quellcode-Beleg im offiziellen Repo, mit Dateipfad. **Test** = Mechanismus plausibel, Test an dieser
Installation nötig. **Annahme** = ausdrücklich offene Annahme. Befunde aus dem lokalen Quellcode trägt
der Orchestrator als **Befund (statisch)**.

## 2. Normative Anker

Basis: RFC 0003 Rev 1 im Repo, gelesen 2026-10-02. Beiträge, die für Netzwerkwege entscheiden:

- **R.4.2** Eine Ausgabe ist ein ganzes Ereignis: Nutzlast, Auswahl, Ziel, Existenz, Reihenfolge,
 modellierte Metadaten. Jede trägt mindestens B_W, auch ein harmloser Request (R.7.1.5).
- **R.4.3** Suchtext und Kennung sind Ausgaben, die Antwort ein neuer Eingang mit eigenem Label.
 Leseberechtigung ist keine Sendeberechtigung. Credentials bleiben beim Connector.
- **R.4.4** Nur ein verbindlicher Vermittler außerhalb der Agentenhoheit erzeugt Außenwirkung.
- **R.5** Basisrechte, Empfängerkreis und Operationsbedingungen werden alle geprüft. Fehlende
 Nachweise ergeben kein permit. Der Agent setzt keine Labels; der Vermittler ordnet sie zu (R.5.5).
- **R.6** Freigaben autorisieren exakte Ereignisse mit Auswahl, Auftreten und Reihenfolge.
 Keine wiederverwendbare Herabstufungsbefugnis.
- **R.3** Zugelassen ist eine konkrete Betreiber- und Laufzeitumgebung, nicht ein Modellname. Ein
 Ausfall erlaubt keinen stillen Fallback.
- **R.8** Der Angreifer bestimmt das gesamte Agentenverhalten, nicht die vertrauenswürdige Basis.
 Vollständige Vermittlung ist Nachweispflicht, einschließlich Hilfsprozessen und Persistenz.
- **R.11** DecisionRecorded, ExecutionCommitted, OutcomeRecorded sind getrennte Ereignisse mit
 dauerhaftem Vorbeleg vor der Wirkung. Der Agent schreibt nichts selbst. Journale sind gebundene
 Daten und dürfen kein Abfluss sein (R.11.5).
- **B.8** Vorprüfungen im Harness sind unverbindlich. Tatsächliche Werkzeugoperationen laufen über
 den kontrollierten Ausführer. Ein übermitteltes permit ist keine Autorisierung.

Einordnung: Ein Egress-Proxy und ein Broker sind nicht von selbst der R.4.4-Vermittler. Ein Broker
kann der Ort sein, an dem Vermittlerprüfungen vor der Wirkung liegen. Ein Proxy kann die durchgesetzte
Netzgrenze liefern und als Effektbelegquelle dienen. Die RFC-Pflichten aus R.11 und B.8 bleiben eigene
Bauarbeit.

## 3. MCP-Sicherheitslage

Spezifikation 2025-11-25, alle Punkte **Doc**, Abruf 2026-10-02. Seiten stehen in Abschnitt 10.

- **Transports.** stdio und Streamable HTTP sind Kerntransporte. Für lokale Server empfiehlt die
 Spezifikation stdio, weil es den Zugang auf genau einen Client begrenzt. Für HTTP-Server verlangt
 sie Localhost-Bindung, Origin-Validierung, Authentisierung und Schutz gegen DNS-Rebinding. Für
 abgeschirmte IPC nennt sie Unix-Domain-Sockets. Lokale Werkzeuge können also rein lokal laufen; ein
 Brokerendpunkt muss sich gegen jeden lokalen Prozess sichern, nicht nur den Agenten.
- **SSRF und Egress-Proxy.** Security-Best-Practices beschreiben SSRF über manipulierte URLs,
 Redirect-Ketten, DNS-TOCTOU und Metadatenendpunkte. Für serverseitige Deployments empfehlen sie
 einen Egress-Proxy, der Netzpolitik gegen interne Ziele grundsätzlich verhindert, mit
 Stripe Smokescreen als Beispiel. Anwendungsschicht-Zielprüfungen lassen sich durch Redirects
 und DNS unterwandern; Durchsetzung sitzt am Verbindungspunkt.
- **Token-Passthrough verboten.** Ein Token, das nicht für den nachgelagerten Dienst ausgestellt
 wurde, darf nicht unverändert weitergereicht werden. Das stützt R.4.3: Credentials halten
 Connector oder Broker, nicht der Agent.
- **Lokale Server-Kompromittierung.** Lokale MCP-Server laufen mit den Rechten des Clients.
 Empfehlung: Sandbox mit minimalen Defaultrechten, eingeschränktem Datei- und Netzwerkzugriff,
 Zusatzrechte nur auf Erteilung. Folge: der AZ-MCP-Server braucht dieselbe Vermittlung wie der Agent.
- **Confused Deputy.** OAuth-Proxyserver mit Consent-Cookies und statischen Client-IDs erlauben
 konsentlose Autorisierung durch Umleitung. Pflichten: pro-Client-Consent, exakte
 Redirect-Validierung, einmalige State-Parameter. Nur relevant, wenn ein Broker OAuth-Flows führt.
- **Scope-Minimierung.** Breite Wildcard-Scopes vergrößern den Schaden kompromittierter Tokens.
  Positiv umgekehrt: hält ein Broker als einziger Credentials, verhindert die Trennung direkten
  Token-Diebstahl durch den Agenten; Missbrauch der Broker-Operationen als Confused Deputy verhindert
  sie allein nicht.
- **Was MCP nicht liefert.** Keine Labelzuordnung, keine Arbeitsraumverträge, kein RFC-Journal und
 keine Bindungserhaltungsnachweise. MCP ist Protokollebene; MCP-Server werden hier als Connectoren
 mit eigener Vermittlungspflicht behandelt.

## 4. Warum Ziel-Allowlist und HTTP_PROXY allein nicht genügen

Eine Ziel-Allowlist beurteilt nur den Zielhost. Nach R.4.2 ist das Ereignis aber die ganze Situation.
Sie prüft nicht:

- ob die Nutzlast einen freigabepflichtigen Suchtext trägt (R.7.3.6 Query-Leak),
- ob Existenz oder Timing der Anfrage Information über den Raumzustand sichtbar macht (R.7.1.5),
- ob die Reihenfolge zugelassener Aufrufe Information transportiert (R.7.2.5),
- ob die Antwort als neuer Eingang mit eigenem Label gedeckt ist (R.4.3).

Bypasswege gegen reine Anwendungsschicht-Pflichten, von der MCP-Doku dokumentiert: Redirect-Ketten
(gültiges erstes Ziel, ungeprüfte Hops), DNS-TOCTOU (safe IP im Prüfschritt, interne IP im
Nutzschritt), und direkte Roh-Socket-Ziele, blind gegenüber Hostname-Allowlisten
(private IP-Blöcke, Cloud-Metadaten, localhost-Dienste).

HTTP_PROXY ist keine Durchsetzung, aus drei Gründen:

1. **Opt-in je Laufzeit.** Node.js honoriert Proxy-Umgebungsvariablen für fetch und http/https
 erst mit NODE_USE_ENV_PROXY=1 bzw. --use-env-proxy (fetch ab Node 24.0, http/https Agent-Sitzung
 ab Node 24.5 bzw. LTS 22.21), sonst laufen diese Aufrufe direkt ins Netz. Dokumentiert in der
 Node-CLI-Doku und den release notes. Bun-Verhalten ist hier ungeprüft (**Test**), und ein
 Sicherheitsgewinn darf daraus nicht geschlossen werden.
2. **TLS-Opacity ohne Termination.** Ohne Termination sieht der Proxy nur die Verbindung: kein
 Nutzlast-Kontrolle, keine Antwortinhalte, keine Labelzuordnung.
3. **Verstellbar durch den Agenten.** Der Agent startet eigene Prozesse und kann Variablen in
 seinem Kontext setzen oder weglassen. Ein Enforcement, das von env-Variablen im Kontext eines
 beliebig handelnden Agenten abhängt, gehört nicht zur vertrauenswürdigen Basis (R.8). Der Proxy
 muss durch OS-Routenbegrenzung garantiert werden; Nachweis beim Sibling-Auftrag.

### 4.4 Proxy-Logs und das RFC-Audit

Gewöhnliche Proxy-Logs sind keine vollständige RFC-Auditstruktur: sie leisten keine Labelentscheidung
und keinen dauerhaften Vorbeleg vor der Wirkung, und die Logs selbst sind gebundene Daten (R.11.5).
Sie können aber eine Rolle im Audit tragen: als Effektquelle für OutcomeRecorded, die der Auditor
gegen die Journalstruktur gegenüberstellt, vergleichbar dem separaten Effektstrom im Simulator
(Anhang C.5). Voraussetzung sind nachgewiesene Authentizität, geschützte Speicherung, Zuordnung zum
passenden Ausführungsversuch und dokumentierter Beobachtungsumfang. Ein nicht interceptierender
Proxy kann innerhalb dieses Umfangs eine Verbindung belegen, nicht die exakte Klartextnutzlast oder
deren semantische Zustellung an die endgültige Domain. TLS-Termination ist für solche
Verbindungsbelege nicht nötig und beweist ihrerseits keine vollständige Abdeckung. Weder ein
separater Proxyprozess noch Namen geplanter Tests sind bereits Evidenz für diese Voraussetzungen
oder vollständige Vermittlung.

### 4.5 Labels auf Antworten

Antwortinhalte externer Quellen sind neue Eingänge (R.2.4, R.4.3). R.2.4 trennt öffentlicher Zugang,
Weiterverwendungsrecht und Nutzung ohne Auflagen. Die Kennung abo-A@3 in RFC 0003 ist ausdrücklich
illustrativ und begründet keine reale rechtliche Einordnung der Allgäuer Zeitung; reale Lizenz- und
Abo-Bindungen sind getrennt zu ermitteln. Klassifikation kann ein Connector nicht unbestimmt
automatisch vornehmen; sie braucht eine berechtigte Stelle oder eine mit dieser Klassifizierung
ausdrücklich freigegebene Importregel (R.2.5). Mit einer solchen freigegebenen Importregel ist eine
automatisierte Klassifikation zulässig.

## 5. Weg-Klassen: Vermittler vor Netzvermittlung

Die entscheidende Ordnung: Ein vertrauenswürdiger Operationsvermittler prüft jede Ausgabe vor der
Außenwirkung. Er trägt das autoritative Raumlabel B_W. Er prüft beabsichtigten Suchtext, Auswahl,
Auftreten und Weg vor der Wirkung. Er fällt bei fehlenden Nachweisen ab, nicht offen weiter.

Credential-Trennung verhindert direkten Diebstahl, nicht den Missbrauch eines berechtigten Brokers
als Confused Deputy. Notwendige, noch ungelöste Entwurfspunkte sind die authentisierte Bindung von
Aufrufer und Arbeitsraum, unveränderliche Request-Bytes und Ziele sowie die Bindung der Ausführung
an den autoritativen aktuellen Zustand (RFC 0003 B.8, R.4.4). Loopback oder ein Socket-Pfadname sind
keine Authentisierung; ein vom Agenten übermitteltes permit ersetzt diese Bindungen nicht (B.8).

Ein Netzproxy kann diesen Vermittler unterstützen. Er erzwingt Zielrichtlinien und liefert
Beobachtungen. Er entscheidet aber keine Labels und keinen Ereignisplan. Proxy allein ist kein
R.4.4-Vermittler.

**Konkrete Kandidaten** (kleine Auswahl, keine Architekturentscheidung):

- Stripe Smokescreen: Egress-Proxy mit Ziel-ACLs; von der MCP-Security-Seite benannt. Stärke:
  Zielrichtlinie am Verbindungspunkt. Grenze: keine Labelentscheidung, kein Vorbeleg.
- mitmproxy: offener HTTPS-Proxy, kann Terminieren, Umleiten, Nutzlasten prüfen und verändern
  (mitmdump mit Python-API). Stärke: belegt, dass ein Logging-Proxy mechanisch machbar ist.
  Grenze: kein RFC-Vermittler; Logs sind eigene gebundene Daten.
- LiteLLM Proxy: Modell-Gateway mit Virtual Keys, Key-Blockierung und Log-Callbacks; eine
  dokumentierte Enterprise-Einstellung verhindert die per-Header-Abschaltung von Callbacks.
  Grenze: keine RFC-Journalpflicht.
- Eigener Vermittler (z. B. in Elixir, getrieben durch das Repo-Prinzip Elixir-first): eng an
  Registry und Engine koppelbar. RFC B.1 lässt die Sprache frei; Elixir-first ist Projektpräferenz,
  keine RFC-Pflicht.

**Sichtbarkeit ist optional.** TLS-Termination ist eine Sichtbarkeitsoption, keine Pflicht. Wenn
der Vermittler jeden Request vor dem Senden erzeugt und prüft, muss der Proxy die Nutzlast nicht
lesen. Ein Logging-Proxy ist dann ein Werkzeug für Auditpfade, nicht eine Voraussetzung für die
Kennzeichnung der Antworten.

**Logs sind selbst gebundene Daten.** RFC 0003 R.11.5 verlangt minimale, geschützte Logs: keine
pauschalen Dokumentkopien, Prompts, Tokens oder Credentials. Ein Proxylog mit vollen Nutzlasten ist
ein zusätzlicher Beobachter und damit selbst ein Prüfobjekt, kein Default. Redaktion und Schutz sind
Teil des Entwurfs, keine Nachzusage.

**Ein optionaler Remote-Modellweg verlangt von sich aus keine Deklassierung.** Nach R.3 ist ein
gewöhnlicher Weg zulässig, solange die konkrete Betreiber- und Laufzeitumgebung von allen
Bindungen in B_W zugelassen ist. Dazu müssen alle tatsächlichen Wege und Beobachter aufgelöst,
gesondert zugelassen und von durchgesetzter Vermittlung erfasst sein: Hauptmodell, Hilfsmodelle wie
Titelgenerierung, Compaction, Cache-Warming und Telemetrie. Unterschiedliche zugelassene Umgebungen
sind möglich, kein stiller Bypass oder Fallback. Ein
ausdrücklich gewählter Modus ist eine Routenwahl, kein pauschaler Inhaltsfreibrief. Freigaben für
einzelne Inhalte bleiben R.6 vorbehalten. Credentials bleiben dabei außerhalb des Agenten (R.4.3).
Netzisolierung allein löst die Kontextfreilegung nicht: ohne Vermittlungsentscheidung kann der
gesamte Raumkontext zum gewählten entfernten Dienst gehen.

## 6. Harness-Integrationspunkte

### 6.1 OpenCode

Provenance: die offizielle Website opencode.ai gehört zu Anomaly und verweist im Header und im
„Edit page“-Link auf github.com/anomalyco/opencode (dev-Zweig). Das Repo gilt damit als offizielle
Quelle; geprüft am 2026-10-02. Verifizierte Konfiguration (jeweils **Doc** oder **Quelle**, mit Status):

| Name | Funktion | Status | Fundort |
|---|---|---|---|
| provider.<id>.options.baseURL | leitet Modellaufrufe zweckgebunden um, dokumentiert für Proxy-Dienste | Doc | docs/providers, „Base URL“ |
| mcp (flaches Objekt, je Server) | MCP-Server lokal (stdio) und entfernt (HTTP) | Doc | docs/config, „MCP servers“; docs/mcp-servers |
| share: manual \| auto \| disabled | Session-Kontexte hochladen; disabled schaltet ab; Default manual | Doc | docs/config, „Sharing“ |
| small_model | eigenes Hilfsmodell für leichte Aufgaben wie Titelerzeugung | Doc | docs/config, „Models“ |
| agent.<name>.disable: true | entfernt einen Agenten inklusive des gebauten Titelagenten | Quelle | packages/opencode/src/agent/agent.ts (dev): title agent ist hidden, primary, native |
| experimental.policies (effect, action „provider.use“, resource) | verbietet oder erlaubt Provider pro policy | Doc | docs/config, „Policies“ |
| disabled_providers / enabled_providers | Provider-Filter; disabled gewinnt | Doc | docs/config |
| autoupdate | Update-Download beim Start; abschaltbar | Doc | docs/config, „Autoupdate“ |
| experimental.disable_paste_summary | verhindert die Zusammenfassungs-Nebenfrage für eingefügte Texte | Quelle | packages/core/src/v1/config/config.ts (dev) |
| Remote-Config .well-known/opencode | wird automatisch beim Provider-Login geholt; eigener Netzpfad | Doc | docs/config, „Remote“ |
| managed settings (MDM/.mobileconfig, /Library/Application Support/opencode) | vom Nutzer nicht überschreibbare Konfigurationseinheiten | Doc | docs/config, „Managed settings“ |

Unverifizierte oder begrenzte Punkte:

- baseURL-Umfang. **Doc** für den Hauptmodellpfad. Für Nebenpfade (Titelagent über small_model,
  Zusammenfassungen) ist die Weiterleitung über baseURL nicht belegt. **Test**.
- HTTP_PROXY-Umgebungsumleitung in OpenCode (Bun). Ungeprüft. **Test**.
- Plugin-Hooks chat.params, chat.headers, experimental.chat.messages.transform,
  experimental.chat.system.transform existieren im dev-Zweig in packages/plugin/src/index.ts
  (**Quelle**), tauchen aber nicht in der offiziellen Plugins-Seite der Ereignisliste auf. Vor
  Nutzung als Integrationspunkt ist die Version zu fixieren. **Test**.
- tool.execute.before und tool.execute.after sind dokumentiert. **Doc** docs/plugins.

### 6.2 pi

Provenance: pi.dev, Betreiber Earendil Inc.; Repo github.com/earendil-works/pi (Paket
coding-agent), Doku im Repo-Ordner docs/. Geprüft am 2026-10-02.

- Extensions laufen im Pi-Prozess mit denselben OS-Rechten. Wörtlich: „An extension runs inside the
  Pi process with the same operating-system permissions.“ **Doc** docs/extensions.
- registerProvider: ein eigener Anbieter. streamSimple: „Implement `streamSimple` only when no
  existing API implementation can represent the service.“ Ein streamSimple-Adapter kontrolliert
  Payload, Transport und Stream-Normalisierung vollständig. **Doc** docs/custom-provider.
- Verbatim: „Provider extensions run inside Pi and can inspect credentials, prompts, tool
  definitions, model responses, and usage. Treat them as trusted code and avoid logging secrets
  or provider payloads.“ **Doc** docs/custom-provider.
- Verbatim payload-Punkt: „Call `options.onPayload` before sending the provider request and use
  any replacement payload it returns.“ **Doc** docs/custom-provider. An diesem Punkt kann ein
  Adapter den zu sendenden Payload prüfen oder einen Ersatz übernehmen und den eigentlichen
  Versandauftrag an einen Vermittler weiterleiten.
- Verbatim Endpunkt-Vorrang: „Model-level `baseUrl` values take precedence over the provider
  endpoint.“ **Doc** docs/custom-provider. Dadurch kann der Modelltransport auf einen lokalen
  Vermittlerendpunkt weisen.
- pi.registerVirtualModel(): „A virtual model is a selectable model that picks a physical model for
  each request“; „`route(request, ctx)` runs before every request made with the virtual model“.
  **Doc** docs/virtual-models. Ein route-Handler wählt Modell und Thinking-Level vor jedem
  Request dieses virtuellen Modells; er ist ein in-process Integrationspunkt und eine Vorprüfstelle.
  Weder Bypassfreiheit noch die Weiterleitung aller Modell-/Nebenpfade ist damit garantiert;
  OS-/Broker-Durchsetzung und ein Abdeckungsnachweis bleiben nötig. **Test**.
- tool_call-Handler können blockieren oder verändern; user_bash-Handler können Shellbefehle
  abfangen. **Doc** docs/extensions.
- Beispiel-Extensions sandbox und permission-gate sind verfügbar (**Doc**, Beispiele, keine
  Komponenten).
- RPC-Modus (JSON-Protokoll über stdin/stdout) und SDK-Modus. **Doc** docs/rpc und docs/sdk. Damit
  kann ein lokaler Steuerprozess pi starten und steuern, während der Pi-Prozess in einem
  Netzisolationsprofil läuft.
- Compaction ist anpassbar; cache_warming_decision kann Hintergrundaufrufe für Prompt-Cache-Warming
  stoppen (action stop). **Doc** docs/extensions. Beide sind Modellpfade, die bei Remote-Modellen
  eigene Vermittlungsobjekte werden.
- Offen: ob in pi weitere Nebenfragen (z.B. Titel-Generierung) existieren und ob alle über denselben
  Adapter laufen. **Test**.
- pi hält Provider-Credentials im Prozess (auth.json). Das widerspricht R.4.3, solange der
  Credential-Halter nicht ausgelagert ist. **Test**.

### 6.3 Hooks sind Vorprüfstellen, keine Enforcement-Grenze

RFC 0003 B.8 trennt unverbindliche Vorprüfungen im Harness vom verbindlichen Ausführer. Ein in-process
Hook kann Nutzlasten sehen und verändern, aber er garantiert nicht, dass nicht ein weiterer Pfad im
Prozess denselben Aufruf direkt ins Netz schreibt.

| Schicht | Ort | Rolle |
|---|---|---|
| OpenCode-Plugin-Hooks, pi-Extensions | im Agentprozess | Vorprüfung und Beobachtung |
| Operationsvermittler (Broker) | eigener lokaler Prozess | Prüfung vor Außenwirkung, Labelentscheidungsvorbereitung, Credential-Halter |
| Netzproxy | lokaler Prozess mit der einzigen Netzroute | Zielrichtlinie, Beobachtung, optional Effektbeleg |
| OS-Netzgrenze | Betriebssystemschicht | verhindert jeden Pfad außer zum Vermittler |
| RFC-Vermittler | eigene Komponente | Labelentscheidung, Vorbeleg, Freigabeabwicklung (R.11, B.8) |

Der R.4.4-Vermittler ist seine eigene Bauarbeit: Labelentscheidung, Vorbeleg und Freigabeabwicklung
sind nicht als Nebenprodukt eines Proxys gegeben. Die OS-Netzgrenze gehört zum Sibling-Auftrag.

## 7. Topologieoptionen

Auswahlentwürfe, keine Entscheidung. Keine der Topologien ist damit konform oder sicher geprüft.

**T1 Rein lokal.** Lokale Inferenz und lokale Tools, keine Route ins Internet. Geringstes
Nachweisvolumen, keine externen Annahmen. Auf macOS/arm64 mit 64 GiB RAM realistisch. Nachteil:
externe Nachrecherche im Fraktionsrecherche-Workflow bleibt aus.

**T2 Lokal plus vermittelter AZ/RIS-Zugang.** AZ-MCP und RIS-Zugang laufen als lokale Prozesse, aber
jede ausgehende Wirkung geht vorher durch einen Operationsvermittler, der B_W autoritativ bestimmt,
Suchtext, Auswahl, Auftreten und Weg prüft und fail-closed entscheidet. Ein Netzproxy mit
connectorbezogen verifizierter Ziel-Allowlist unterstützt diese Begrenzung und liefert
Beobachtungen. allgaeuer-zeitung.de ist ein AZ-Zielbeispiel, keine vollständige Allowlist.
ris.komuna.net ist der historische HTML-Weg; die aktuelle RIS-Abrufbasis im Repo ist
risapi1.komuna.net (api_client.ex:5-8). Konkrete RIS-API-/Auth-Hosts und Redirects müssen pro
Connector verifiziert werden. TLS-Termination ist optional: Verbindungsbelege im dokumentierten Beobachtungsumfang
sind auch ohne sie möglich, exakte Klartextnutzlast und semantische Zustellung an die endgültige
Domain dadurch aber nicht belegt (Abschnitt 4.4). Termination beweist keine vollständige Abdeckung.
Credentials halten Vermittler oder Connector, nicht der Agent.
Antwortlabels entstehen nach einer für diese Klassifizierung freigegebenen Einordnung, nicht durch
den Agenten. Vorteile von T2: minimaler Betrieb, die Vermittlungsentscheidung liegt vor der Wirkung,
Connector-Credentials sind vom Agenten getrennt. Nachteil: die Vermittlungspunkte für
Connector-Anfragen und die Labelvergabe der Antworten sind eigene Bauarbeit; die Allowlist allein
ist keine Vermittlungsentscheidung.

**T3 Remote-Modellweg über den Vermittler.** Standard bleibt lokale Inferenz. Optional laufen
Remote-Modellaufrufe nur über einen lokalen Operationsvermittler, der Credentials hält, Endpunkte
prüft und fail-closed schaltet. OpenCode-Anbindung über provider.<id>.options.baseURL (Hauptpfad,
**Doc**), für Nebenpfade unbestätigt. pi-Anbindung über streamSimple bzw. registerVirtualModel
(**Doc**). Der Vermittler läuft bevorzugt über lokale IPC, etwa Unix-Socket, wie die MCP-Doku für
abgeschirmte IPC empfiehlt.
- Nach R.3 ist der Vermittler ein gewöhnlicher Weg, wenn die gewählte entfernte Umgebung von allen
 Bindungen in B_W zugelassen ist. Inhaltsfreigaben brauchen R.6-Freigaben separat.
- Fail-Verhalten: fällt der Vermittler aus, fällt der Remote-Modellweg aus. Kein stiller Fallback.
- Beschränkung: jeder tatsächliche Nebenpfad und Beobachter (etwa Titel, Compaction, Telemetrie)
 muss aufgelöst, autorisiert und von durchgesetzter Vermittlung erfasst sein. Unterschiedliche,
 jeweils gesondert zugelassene Umgebungen sind möglich; kein stiller Bypass oder Fallback.
 Ein gemeinsamer Vermittler ist die minimale geplante Topologie, keine normative
 Ein-Provider-Pflicht. (R.8.2, R.3.)

**T4 Remote-Modell nur nach begrenzter Faktenfreigabe.** RFC 0003 Workflow B (R.7.2): der geschützte
Raum produziert einen Faktenbestand, eine berechtigte Stelle gibt das exakte Ereignis frei, und ein
neuer öffentlicher Raum erhält nur diese Fakten und öffentliche Vorgaben. Nur dieser Raum greift
optional auf entfernte Modelle zu. Stärkste Zusage bezogen auf den entfernten Kontext. Begrenzte
Faktenfreigabe ist eigene Bauarbeit; der öffentliche Raum braucht einen eigenen Startvertrag,
keinen ungeprüften Rückkanal.

## 8. Entscheidungsfragen

Nur echte Entscheidungen, keine Nachschlagefakten (diese sind in Abschnitt 6 verifiziert).

1. Reihenfolge der Lerniteration: erst T2 (vermittelter AZ/RIS-Zugang), dann optional T3, oder
 beides zusammen?
2. Entfernte Umgebungszulassung: welche konkrete Betreiber- und Laufzeitumgebung wird für einen
 optionalen Remote-Modellweg in Erwägung gezogen, und sind alle Nebenpfade in ihr erfasst? (R.3)
3. Reale AZ-Rechtsgrenzen: welche Abo- und Lizenzbindungen gelten real? Verbindlich ist nur die
 Illustration abo-A@3 im RFC; reale Bindungen sind separat zu ermitteln. (R.2.4)
4. Journalbindung: wie ist ein späteres Proxylog oder ein Logging-Proxy als Effektbelegquelle an
 das RFC-Journal zu binden, ohne selbst zu einem Abfluss zu werden? (R.11)
5. OS-Netzgrenze auf macOS/arm64: hinreichend und nachweisbar? Zuständigkeit Sibling-Auftrag;
 hier nur Abgrenzung, keine Sicherheitsbeurteilung.

## 9. Evidenzstatus und Grenzen

### 9.1 Statische Befunde aus lokalem Quellcode

Vom Orchestrator lokal geprüft; keine Live-Prüfung, keine Laufzeittests. Kennzeichnung:
**Befund (statisch)**.

- Allgäuer Zeitung MCP (tools/allgaeuer_zeitung_mcp, Quellpfad src/newspaper_mcp/):
  - server.py:93-106: get_article nimmt eine beliebige URL entgegen und holt sie. Der Serverpfad
    braucht deshalb die Vermittlung wie jeder andere Prozess.
  - client.py:97-115: fetch_article_html fällt bei gekürztem Body auf Playwright zurück, das JS
    ausführt und die Subscriber-Version lädt. Die Allowlist am Netzweg muss Redirects und den
    Browser-Fallback einschließlich möglicher weiterer Browseranfragen abdecken. Schon normales
    AZ-Fetching nutzt Session-Cookies; dieser Pfad ist keine Autorisierung als public-only sichere
    Quelle.
  - client.py:30-48: der httpx-Client nutzt einen domain- und pfad-scoped Cookie-Jar und
    follow_redirects=True. Die These, alle Cookies gingen an beliebige Domains, ist falsch.
    Statisch sichtbar in client.py:30-35: Domain und Pfad werden gesetzt, das secure-Flag wird
    nicht erhalten. Das Risiko hängt von akzeptierten URL-Schemas und Cookie-Metadaten ab; ein
    tatsächlicher Leak ist nicht bestätigt. Laufzeitverhalten im vermittelten Pfad bleibt offen
    (**Test**); hierfür wurden keine Credentials oder Cookies inspiziert.
- RIS-Zugang (apps/ratsinfo): die lokale FTS-Abfrage (store.ex:187-202) hat überhaupt keinen
 Zugriffsfilter; tops.restricted ist gespeichert (store.ex:125) und geht ungefiltert in die
 Suche ein. Eine Existenz- oder Statusasymmetrie der Treffer ist ein möglicher Auswahleffekt.
 Das entspricht strukturell dem in D.3 modellierten Muster, ist aber keine vorhandene
 Implementierung von „erst Top-k, dann Filter“ und keine reproduzierte D.3-Abnahme.
 Ein vollständiger Nachweis bleibt **Test**.

### 9.2 Weitere Grenzen

- Keine Freigabe geschützter Daten. Der Bericht enthält keine Freigabefakten. Die bestehende
 synthetische Policy-Konfiguration im Repository kann nicht als Live-Autorität verwendet werden,
 ohne einen eigenen Vertrag über Realeinsatz.
- Keine konformitäts- oder sicherheitsbezogenen Behauptungen über eine unverbaute Topologie; jede
 solche Aussage ist eine Unklarheit, kein verzögerter Test.
- Kein Commit oder Push; kein Veröffentlichungsbeschluss. Der Bericht ist für den Orchestrator
 geschrieben.

## 10. Quellen

Alle Quellenabrufe: 2026-10-02.

- RFC 0003 Rev 1, docs/rfcs/0003-vertrauliche-ki-arbeitsraeume.md (Repo-Stand 2026-10-02).
- MCP-Spezifikation 2025-11-25, Basic/Transports:
 modelcontextprotocol.io/specification/2025-11-25/basic/transports
- MCP-Spezifikation 2025-11-25, Basic/Authorization:
 modelcontextprotocol.io/specification/2025-11-25/basic/authorization
- MCP-Spezifikation 2025-11-25, Security_Best_Practices:
 modelcontextprotocol.io/specification/2025-11-25/basic/security_best_practices
- OpenCode (offiziell): opencode.ai gehört zu Anomaly; Repo github.com/anomalyco/opencode. Seiten:
 docs/config, docs/providers (Base URL), docs/plugins, docs/mcp-servers.
 OpenCode-Quellcode (dev-Zweig): packages/opencode/src/agent/agent.ts (Titelagent, disable),
 packages/plugin/src/index.ts (chat.params, chat.headers, experimental.chat.messages.transform,
 experimental.chat.system.transform), packages/core/src/v1/config/config.ts
 (experimental.disable_paste_summary), packages/opencode/src/session/session.ts (isDefaultTitle).
- pi (offiziell): pi.dev, Repo github.com/earendil-works/pi, Paket coding-agent. Doku:
 docs/extensions.md, docs/custom-provider.md, docs/virtual-models.md, docs/rpc.md, docs/sdk.md,
 README.md.
- mitmproxy: mitmproxy.org („interactive HTTPS proxy“; „inspect, modify and replay“).
- Stripe Smokescreen: github.com/stripe/smokescreen (von der MCP-Security-Seite als Beispiel genannt).
- LiteLLM: docs.litellm.ai (Virtual Keys, /key/block; Disable Dynamic Callback Management).
- Node.js: nodejs.org/api/cli.html (node_use_env_proxy1).
- undici: github.com/nodejs/node/blob/main/deps/undici/src/docs/docs/best-practices/undici-vs-builtin-fetch.md.

## 11. Kurzfassung

- Genügt nicht: eine Ziel-Allowlist und ein HTTP_PROXY allein. Sie beurteilen nur eine Teilmenge
 des Ereignisses (R.4.2) und liegen in der Verantwortungsumgebung des Agentenprozesses.
- Struktur statt: ein Operationsvermittler vor der Außenwirkung mit autoritativem B_W, Prüfungen
 für beabsichtigten Suchtext, Auswahl, Auftreten und Weg, fail-closed Verhalten, Credentials
 außerhalb des Agenten.
- Ein Netzproxy unterstützt Zielrichtlinie und Beobachtung; er ist keine Vermittlungsentscheidung.
 TLS-Termination ist eine Sichtbarkeitsoption; minimale, geschützte Logs statt voller Nutzlasten
 (R.11.5).
- Proxy-Logs sind keine vollständige RFC-Auditstruktur. Als Effektbelegquelle sind sie nur bei
 nachgewiesener Authentizität, geschützter Speicherung, Zuordnung zum passenden Ausführungsversuch und
 dokumentiertem Beobachtungsumfang verwendbar; diese Voraussetzungen sind hier nicht getestet.
- Ein gewöhnlicher unbefristeter Weg ist zulässig, wenn eine konkrete entfernte Umgebung von allen
 B_W zugelassen ist (R.3). Ein ausdrücklich gewählter Modus ist keine pauschale Inhaltsfreigabe.
- OpenCode und pi bieten verifizierte Integrationspunkte, aber Hooks sind in-process und
 Vorprüfstellen, keine Enforcement-Grenze (B.8).
- Keine Topologie wird hier als RFC-konform oder sicher bezeichnet. Isolation und Audit sind nicht
 getestet; benannte Testvorhaben oder getrennte Prozesse ersetzen keine tatsächlichen Nachweise.
