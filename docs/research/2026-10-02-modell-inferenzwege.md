# Modell- und Inferenzwege für die erste Lerniteration

Recherchebericht zu Issue 69 „Welche Modell- und Inferenzschnittstellen tragen den Lernbetrieb?"
(Repo croesnick/kommunalpolitik_ki). Stand und alle Quellenabrufe: 2026-10-02.
Zusätzlich verifiziert: ollama 0.34.2, llama.cpp (llama-server) 0.4.1 build b29c606e2,
opencode 1.18.34, pi 1.0.0 (siehe Abschnitt 2).

| Feld | Wert |
|---|---|
| Art | Primärquellen-Recherche (Doku, Modellkarten, --version-Diagnostik) |
| Versionsschere | Installierte Versionen (Abschnitt 2) sind lokal verifiziert. Die hier zitierte Doku stammt von upstream main bzw. master zum Abrufdatum 2026-10-02 ohne Commit-Pin; ob jedes dokumentierte Merkmal in der installierten Version vorhanden ist, ist offen |
| Grenze | Keine Installation, kein Modell-Download, kein Serverstart, keine Inferenzaufrufe, keine Provider-Auth- oder Secret-Zugriffe, keine Benchmark. Zusätzlich: die im Berichtsverlauf abgesetzten Runtime-Metadatenabfragen (ollama list, GET /api/tags, GET /health) lagen über dem beauftragten Doku- und --version-Umfang; sie sind rein lesend geführt und belegen Sichtzustand, keine Qualität, keine Sicherheit, keine historische Vorgeschichte |
| Subset | Kleine Kandidatenmenge: Ollama, llama.cpp/llama-server, kurz MLX; anhand von Modellkarten beschriebene Familien Qwen3 und Mistral Small 3.x |
| Basis | RFC 0003 Rev 1; Forschungsbericht „Vermittelte Agent-Netzwerkwege" (Rev 1) |

## 1. Auftrag und Leseweg

Gefragt ist, welche dokumentierten lokalen Modell- und Inferenzwege auf dem bestehenden Host
macOS arm64, Apple M1 Max, 64 GiB für dokumentengebundene private Entwürfe in OpenCode oder pi
tragfähig sind. Lokal ist bevorzugt, nicht zwingend; ein ausdrücklich wählbarer Remote-Weg bleibt
möglich (Vermittlungspunkte im Bericht „Vermittelte Agent-Netzwerkwege", Rev 1, 2026-10-02).

Evidenzstufen je Befund: **Doc** = offizielle Dokumentation (URL und Abrufdatum). **Fakt (lokal)** =
durch schreibgeschützte Diagnostik auf diesem Host verifiziert. **Est** = rechnerische Schätzung aus
dokumentierten Parametern, kein Test. **Unbekannt** = nicht experimentell abgedeckt und nicht
dokumentiert.

Deutlich getrennt bleiben: Inferenzrouten (Chat- und Completion-Endpunkte, die der
Operationsvermittler später freigibt) von Management-APIs (Download, Delete, Blob-Upload), die
Außenwirkungen erzeugen können. Kein Modell wird hierfür jetzt zugelassen; Kontextbedarf und
Quantisierung wählt der Mensch später.

## 2. Verifizierte Lokalfakten und Diagnostik-Einordnung

Alle Punkte in diesem Abschnitt stammen aus schreibgeschützten lokalen Diagnostik-Befehlen. Zwei
Kategorien lagen im beauftragten Umfang: Versionsabfragen (--version) und Befehlsfeststellung
(command -v). Drei weitere Runtime-Metadatenabfragen (ollama list, GET /api/tags, GET /health auf
8080) lagen **über** dem beauftragten Umfang. Sie sind rein lesend geführt und bewusst im Bericht
belassen. Einordnung:

- Sie belegen nur den beobachteten Zustand zum Abfragezeitpunkt (Storeinhalt bzw. ein
  antwortender Ollama-Daemon); kein historisches Vorher, keine Qualität, keine Sicherheit.
- Sie sind keine Grundlage für Speicher- oder Kapazitätsurteile (Abschnitt 5).

Faktenliste:

- Befehle vorhanden: ollama, llama-server, llama-cli, llama-bench auf dem PATH (Homebrew-Pfade
  unter /opt/homebrew/bin; opencode unter ~/.bun/bin, pi über asdf shims).
- Versionen (read-only --version-Diagnostik): ollama 0.34.2; llama-server 0.4.1 (build 10964,
  commit b29c606e2); opencode 1.18.34; pi 1.0.0.
- Host: hw.memsize = 68719476736 bytes = 64 GiB physisch. sysctl iogpu.wired_limit_mb = 0;
  der tatsächlich wirksame GPU-Speicher-Default auf dieser Maschine bleibt **Test**.
- ollama list zeigte einen Eintrag qwen3:30b-a3b mit der Größenangabe 18 GB (roher Wert
  18556699314 bytes, dezimal angezeigt; entspricht rund 17.3 GiB). Das ist ein Metadatenwert des
  Modelstores: die belegte Größe des Modellartefakts auf dem Datenträger. Es ist
  **keine** Messung von Residenzspeicher, Cachebelegung oder Zuweisungsgröße im Betrieb. Auch ist es
  keine Aussage über die Quantisierung oder den Größenanteil der Gewichte an der Datei.
- Ein GET /api/tags (auf Port 11434) wurde synchron beantwortet. Das belegt einen zum Abfrage-
  zeitpunkt antwortenden lokalen Ollama-Daemon; kein Inferenzabruf, kein Download, keine Änderung.
  Der Zustand zeitlich vor der Diagnostik ist daraus nicht ablesbar und bleibt **Unbekannt**.
- GET /health auf Port 8080, keine Antwort: das belegt nur, dass auf diesem Port zum
  Abfragezeitpunkt kein Server antwortete. Es ist **kein** Beweis, dass kein llama-server weiter
  auf diesem Host läuft (etwa auf anderem Port oder mit anderer Bindung). Kein Daemon-Scan. Die
  Suche nach Servern und beobachtbaren Routen gehört in eine spätere Testphase.

## 3. Laufzeitvergleiche: Ollama und llama.cpp/llama-server

Beide Pakete sind installiert (Abschnitt 2). Die tabellarischen Merkmale stammen aus der
upstream-Doku: Ollama docs auf main und llama.cpp tools/server/README.md auf master, beide
Abruf 2026-10-02, ohne Commit-Pin. Die installierten Versionen sind dabei nicht identisch
verifiziert: was in der Doku der main/master-Linie steht, kann in ollama 0.34.2 bzw.
llama-server 0.4.1 anders aussehen. Versionsspezifische Verifikation bleibt **Test**.

| Frage (upstream-Dokumentation, nicht versionsspezifisch abgeglichen) | Ollama (Doku main; installiert: 0.34.2) | llama.cpp/llama-server (Doku master; installiert: 0.4.1) |
|---|---|---|
| Inferenz-Endpunkte | POST /api/chat, POST /api/generate (nativ); OpenAI-kompatibel /v1/chat/completions, /v1/completions; /v1/embeddings für Retrieval | POST /v1/chat/completions, /v1/completions, /v1/responses, /v1/embeddings; auch POST /v1/messages (Anthropic-kompatibel), GET /v1/models |
| Werkzeugaufrufe | /api/chat nimmt tools (OpenAI-Form) entgegen; Antworten tragen tool_calls | OpenAI-ähnliche Toolaufrufe nur mit --jinja; Templatequalität modellabhängig, Worst-case --chat-template chatml |
| Strukturierte Ausgabe | format: "json" oder JSON-Schema in /api/chat und /api/generate | response_format json_schema bzw. --json-Flag |
| Modellwahl | Modellname pro Request, bezogen auf den lokalen Store (dokumentiert) | Modell wird beim Start über -m Pfad geladen (dokumentiert); Verhalten bei Frage zur Laufzeitmodellwahl hier nicht belegt |
| Download/Management | POST /api/pull (Downloads), /api/push, DELETE /api/delete, POST /api/copy, POST /api/create + /api/blobs (dokumentiert) | Die zitierte README dokumentiert Startoptionen --hf/--model-url/--docker-repo (Fremdladung im Startkommando). Ob es weitere Steuer- oder Verwaltungswege gibt, ist hier nicht vollständig untersucht; die Liste benennt belegte Wege und behauptet nicht die Abwesenheit weiterer Wege. |
| Absicherung | Bindung localhost:11434; Doku zeigt keine API-key-Pflicht | Bindung 127.0.0.1:8080; optional --api-key (mehrere Keys möglich), /health offen ohne Auth |
| Streaming | stream: true als Default bei /api/chat und /api/generate | Streaming je Endpunkt; Slots mit -np, Überwachung über /slots |

Wichtige Grenze der Tabelle: Nur die **positiv beschriebenen** Routen sind aufgeführt. Die Listen
sind **keine Zusicherung einer vollständigen Sicherheits-Allowlist**: Slots, Zustands- und Kontrollrouten
(llama.cpp: /slots), umgeleitete Modellpfade und alternative Dispatch-Modi können je Version oder
Startmodus zusätzliche Wege öffnen. Ein Broker-Kontrakt darf daher nur positiv benannte Endpunkte
freigeben und muss fail-closed auf alles Unbenannte (Entwurfsoption, Abschnitt 7). Ollamas
Cloud-Dispatch wird gesondert in Abschnitt 7 behandelt.

Der Apple-Silicon-spezifische Kandidat: **MLX** (Apple MLX, mlx-lm) ist eine dokumentierte
Plattform für lokale Inferenz auf Apple Silicon mit Servermodus. Diese Recherche hat MLX bewusst
klein gehalten: Werkzeugaufrufe und konkrete Harness-Anbindung sind hier **Unbekannt** (kein
Test). MLX bleibt Spezialoption, falls die Geschwindigkeit von Ollama oder llama.cpp in der Praxis
merklich unzureichend ausfiele. Es ist der einzige weitere Laufzeitkandidat dieser Abfrage.

## 4. Vergleich Modellfamilien

Zwei anhand von Modellkarten beschriebene Familien (Abruf 2026-10-02). Keine Qualitäts- oder Performance-Aussage wird aus
RAM, Binärdateien oder max-context-Angaben abgeleitet; alle Qualitätsangaben bleiben
Karten-Assertionen, keine Host-Verifikation, bis ein Test läuft.

| Merkmal | Qwen3 30B-A3B (MoE) | Mistral Small 3.2 24B (2506) |
|---|---|---|
| Lizenz laut Modellkarte (keine vollständige Lizenzprüfung) | Apache-2.0 | Apache-2.0 |
| Kontextfenster | 32,768 nativ; 131,072 mit YaRN (Karte) | 128k: Karte 3.1 nennt „long context capabilities up to 128k tokens"; die 3.2-Karte nennt kein eigenes Kontextfenster und verweist für alle anderen Kategorien auf „match or slightly improve" gegenüber 3.1 |
| Architektur | MoE 30,5B total / 3,3B aktiv; 48 Layer; GQA 32 Q-/4 KV-Köpfe; 128 Experten / 8 aktiv | Dense 24B; BF16 (Karte); Kartennotiz: ca. 55 GB GPU-RAM in bf16/fp16 |
| Werkzeuge | Tool- und Agent-Kapazität in Think- und No-Think-Modus; Qwen-Agent empfohlen | Funktionsaufrufe mit robusterem Template (Karte 3.2 nennt Verbesserung gegenüber 3.1) |
| Sampling | Thinking: temp 0.6, TopP 0.95, TopK 20; No-Think: 0.7/0.8/20; Karte warnt vor greedy | Karte empfiehlt niedrige Temperatur (0,15) und einen Systemprompt |
| Modellkarte (ohne Revision-Pin) | huggingface.co/Qwen/Qwen3-30B-A3B | huggingface.co/mistralai/Mistral-Small-3.2-24B-Instruct-2506 |

Die Modellkarten nennen Apache-2.0 für diese Familien. Das ist keine vollständige Prüfung der
Laufzeit-, Artefakt- oder Quantisierungslizenzen; diese müssen vor tatsächlicher Abhängigkeit oder
Nutzung gesondert geprüft werden. Die endgültige Modellwahl bleibt eine menschliche Entscheidung.

## 5. Gewichts- und KV-Cache-Budget

Rechnung und Schätzung (**Est**). Für einen Raumkontext gelten drei Größen:

- Gewichtsspeicher: Parameteranzahl × Bytes pro Parameter (Quantisierung);
- KV-Cache: 2 × Layer × KV-Köpfe × head_dim × Kontexttoken × Bytes pro Element (Cache-Typ);
- Host-Budget: 64 GiB physisch; die nutzbare Grenze für GPU-Wired-Memory hängt vom
  macOS-Wired-Limit ab (sysctl iogpu.wired_limit_mb). Der wirksame Default auf dieser Maschine ist
  hier **Unbekannt** und braucht **Test**.

Konkret zum vorliegenden Befund:

- Die Angabe 18 GB aus ollama list ist die **Belegungsgröße des Modelartefakts im Store**
  (Datenträger, roher Wert 18556699314 bytes), **Fakt (lokal)**. Sie ist **keine** Messung von
  Residenzspeicher im Betrieb, keine Aussage über die konkrete Quantisierung und kein Beleg
  einer Gewichts-KV-Zerlegung.
- Die nachfolgenden Formelwerte sind bedingt: die Qwen3-Karte nennt 48 Layer und 4 KV-Köpfe,
  aber nicht head_dim; die folgende Schätzung nimmt head_dim = 128 an (config.json wurde hier
  **nicht** gelesen). Dann wäre der KV-Cache (2 × 48 × 4 × 128 × 2 Byte) ≈ 96 KiB pro Token bei
  f16, ein 128k-Kontext ergäbe rechnerisch etwa 12 GB KV, ein 32k-Kontext etwa 3 GB. Das ist
  **Est**, kein Messwert.
- Es wird **keine** tragfähige Passung aus der physischen 64-GiB-Grenze abgeleitet. Der reale
  Bedarf von Gewichten, KV-Cache und OS-Budget im laufenden Betrieb ist **Unbekannt** und braucht
  beim ersten Ladeversuch ein Mess- und Abbruchsprinzip. Die Modell-, Kontext- und
  Quantisierungswahl bleibt eine spätere menschliche Entscheidung.

## 6. Anbindung an OpenCode und pi

Die installierten Harness-Versionen sind als lokale Fakten verifiziert: opencode 1.18.34, pi 1.0.0.
Doku-Abruf 2026-10-02. Verifizierte Integrationspunkte (Kurzfassung; Details im älteren Bericht
„Vermittelte Agent-Netzwerkwege", Rev 1, 2026-10-02):

- **OpenCode**: lokaler Anbieter über provider.<id>.options.baseURL; die offizielle Doku listet
  dokumentierte lokale Basis-URLs, darunter Ollama http://localhost:11434/v1 und llama.cpp-Server.
  Wie im älteren Bericht gilt: baseURL ist für den Hauptmodellpfad dokumentiert, Nebenpfade sind
  **Test**.
- **pi**: Ollama ist dokumentiert als kompatibler Endpunkt in models.json, mit Beispiel
  baseUrl http://localhost:11434/v1, api "openai-completions", und einem Dummy-Key („The dummy
  key makes the model available to Pi; Ollama ignores it."). Für llama.cpp-Server gilt dasselbe
  Muster über OpenAI-kompatible Endpunkte.

Der ältere Bericht bleibt gültig für die Vermittlungsstruktur: Operationsvermittler vor
Außenwirkung, Netzproxy nur als Unterstützung. Der lokale Modellpfad ändert die Struktur nicht:
der Vermittler sitzt weiterhin zwischen Harness und Inferenzendpunkt.

## 7. Endpunktfläche für den Operationsvermittler

**Status: Entwurfsoption, keine Freigabe.** Die folgenden Listen sind eine Designoption für einen
späteren Broker-Contract. Eine Endpunkt-Erlaubnisfläche ist **keine Effektautorisierung**: die
verbindliche Autorisierung von Ausgaben bleibt Sache der RFC-0003-Pflichten (R.5, R.6, R.11) und
wird erst in der Abnahme belegt. Im RFC-Kalkül gilt permit/deny/indeterminate mit vollständigen
Nachweisen, nicht nur URI-Matching (R.5.2, B.8). Grundprinzip der Designoption: Inferenzrouten
erlauben, Managementrouten verweigern, fail-closed auf alles Unbenannte.

Vorgeschlagene Inferenzrouten (positiv benannt, je nach gewählter Laufzeit):

- OpenAI-kompatible Route: POST /v1/chat/completions (Hauptpfad für Chat und Toolaufrufe).
- Optional für Retrieval: POST /v1/embeddings.
- Optional, nicht default: GET /v1/models für einen Manifestabgleich; es **darf** nicht als
  Default-Enumeration privater oder lokaler Modelllisten laufen.
- Ollama-native Alternative: POST /api/chat statt der OpenAI-Route.
- llama.cpp-spezifisch: POST /v1/messages nur, wenn der Harness sie konkret nutzt.

Ausgeschlossene bzw. zu prüfende Management- und Steuerpfade:

- Ollama: POST /api/pull (löst Modell-Downloads aus), POST /api/push, DELETE /api/delete,
  POST /api/copy, POST /api/create, POST /api/blobs/:digest. Auch GET /api/ps bleibt außerhalb
  der vorgeschlagenen Fläche, weil sie Betriebszustand offenlegt.
- llama.cpp: die Startoptionen --hf, --model-url und --docker-repo können beim Start Fremdmodelle
  laden. Das steht so in der zitierten upstream-README; ein Commit-Pin gegen die installierte
  Version 0.4.1 fehlt (kein Quellenabgleich). Entwurfsoption: In einem vermittelten Start dürfen
  diese Flags nicht vorkommen; geladen wird nur über -m mit lokalen Pfaden aus dem geprüften
  Modellbestand.
- Die Aussage „diese Flags dürfen nicht vorkommen“ ist eine Entwurfsregel der ersten Iteration,
  keine verallgemeinerte RFC- oder Sicherheitsgarantie. In anderen Versionen oder Startmodi
  können zusätzliche Steuer-, Cache- oder Kontrollpfade existieren; der Broker-Contract muss sie
  bei seiner Implementierung enumerieren, nicht davon ausgehen, dass die Tabelle oben
  vollständig ist (siehe auch die Tabellennote nach Abschnitt 3).

**Verbindlichkeit des Modellidentitätsvertrags.** RFC 0003 erhebt keine Pflicht, einen Modellnamen
dauerhaft unveränderlich zu pinnen. R.3 sagt: Ein Modellwechsel kann dieselbe oder eine andere
zugelassene Umgebung verwenden. Ein gepinnter Modellname mit Quellenangabe und Digest ist daher
eine vorgeschlagene Einschränkung der ersten Iteration (Designoption), keine generell geteilte
RFC-Pflicht. Der Vermittler-Kontrakt könnte für die erste Iteration unabhängig davon einen
konkreten Modell-/Artefaktvertrag festlegen und dabei:

- die Modellidentität (Name, Quelle, Digest, Quantisierung) und die Backend-Lokalität an den
  Raumvertrag binden,
- Modellnamen nicht als freien Requestparameter zulassen (Modellwahl ist eine Raum- und
  Auswahlentscheidung),
- bei einer Modelländerung tatsächliche Änderungen an Wegen und Beobachtern prüfen und bei Bedarf
  eine neue Zulassung einholen (R.3); ein Modellwechsel kann auch innerhalb derselben zugelassenen
  Umgebung stattfinden. Modellname oder Cloud-Suffix allein belegen keine lokale Verarbeitung.

**Cloud-Weg in Ollama als Nebenpfad.** Die Ollama-Doku zur OpenAI-Kompatibilität beschreibt für die
aktuelle main-Linie: ein angemeldeter lokaler Server kann Cloud-Modelle im /v1-Weg bedienen; ein
Cloud-Modellname (z. B. „...:cloud") kann nach Anmeldung ohne Pull verwendet werden. Die Doku nennt
auch Grenzen: die Cloud-API unterstützt keine stateful Responses, keine Web-Suche in /v1/responses
und kein custom/freeform-tool-call-replay. Das ist ein Umgebungsfaktor (**Doc**, Abruf 2026-10-02,
docs/api/openai-compatibility.mdx). Ob die installierte Version 0.34.2 dieses Verhalten bereits
hat, ist hier nicht geprüft (**Test**). Konsequente Entwurfspunkte, unabhängig davon:

- Der Operationsvermittler bindet Modellname, Quelle und Digest an den Raumvertrag; Modellwahl ist
  eine Raum- und Auswahlentscheidung, kein freier Requestparameter des Clients.
- **Nicht beschriebene bzw. stille Cloud-Dispatch bleibt ausgeschlossen**: Wenn eine Anfrage an
  ein Modell weitergeleitet wird, ohne dass der Weg in der Umgebungszulassung beschrieben ist,
  fehlt die Evidenz für den vollständigen Weg (R.3,R.8.2); sie wird fail-closed abgewiesen.
- **Ein ausdrücklich beschriebener und autorisierter Remote-Weg bleibt Kandidat**: Der Auftrag
  lässt optionalen Remote-Modelleinsatz ausdrücklich zu. Ein Cloud-Dispatch, der als eigener Weg
  mit eigener Zulassung beschrieben ist, braucht eine eigene Umgebungszulassung (R.3), kein
  pauschales Ausschlussurteil. Kein Remote-Weg wird hier freigegeben.

## 8. Bekannt und nicht bekannt

Dokumentiert (aus den zitierten Quellen abrufbar, upstream-Stand, nicht an die installierten
Versionen abgeglichen):

- Endpunktflächen beider Laufzeiten in den zitierten Doku-Dateien inkl. Toolsignaturen und
  strukturiertem Output.
- Kontext, Sampling-Leitlinien und Lizenzangaben der beschriebenen Familien (Karten-Assertionen, keine
  Host-Verifikation).
- Der Modelstore enthält ein Artefakt qwen3:30b-a3b mit Metadatengröße 18 GB (lokal gelesen).

Nicht belegt (bleibende Unklarheiten):

- Tatsächliche Antwortqualität und Toolcalling-Robustheit der Kandidatenmodelle auf diesem Host,
  für jede betrachtete Quantisierungsvariante. **Unbekannt**.
- Realer Gesamtspeicherbedarf von Gewichten plus KV-Cache im laufenden Betrieb und realer nutzbarer
  Kontext. Die 96-KiB-Schätzung ist Formelrechnung unter der Annahme head_dim = 128,
  kein Messwert.
- Verhalten bei Quantisierungsvarianten (KV-Quant wie q8_0/q4_0; Quantstufen der Store-Artefakte).
  Die Wahl bleibt eine spätere menschliche Entscheidung.
- Das macOS-GPU-Memory-Limit (iogpu.wired_limit_mb) und die tatsächlich nutzbare Speichergrenze im
  Betrieb.
- Versionsspezifische Deckung zwischen installierten Versionen und zitierten Doku-Dateien (Commit
  hinsichtlich Pinning).
- Vollständige Endpunkt- und Steuerpfad-Enumeration beider Laufzeiten in installierten Versionen.

## 9. Kleine Richtungsempfehlung (keine HITL-Entscheidung)

- Die installierte Ollama-Version 0.34.2 mit dem bestehenden Store-Artefakt qwen3:30b-a3b
  (Metadatengröße 18 GB) ist der direkteste Startpunkt für eine erste Lerniteration, API-Weg
  POST /api/chat oder die OpenAI-kompatible Route; Qualität bleibt abzuprüfen (**Unbekannt**).
- llama.cpp (llama-server 0.4.1, b29c606e2) ist die Alternative, wenn explizite Steuerbarkeit im
  Vordergrund steht: Flags -m, -c, KV-Quant (-ctk/-ctv), --jinja für Toolcalls. Die zitierte Doku
  beschreibt keine Pull-/Delete-Verwaltungsfläche; das ist positiv formuliert, keine Aussage über
   vollständige Abwesenheit in allen Versionen. Geladen werden soll aus dem geprüften lokalen
  Modellbestand über feste Pfade.
- pi bindet beide Wege über models.json (kompatibler-endpoint-Muster), OpenCode über
  provider options.baseURL; beide Anbindungen sind dokumentiert; Harness-Nebenpfade bleiben offen.
- Alle Wege laufen nach RFC 0003 nur über den Operationsvermittler; Managementflächen sind
  innerhalb der vorgeschlagenen Contract-Designoption ausgeschlossen; die erste Lerniteration
  arbeitet mit synthetischen und ausdrücklich autorisierten öffentlichen Daten.

## 10. Anknüpfungspunkte für spätere Issues

- Die Vermittler-Endpunktfläche aus Abschnitt 7 ist ein Ausgangspunkt für das spätere
  Implementationsticket; sie bleibt Entwurfsoption bis zur Abnahme.
- Der Modellbestand braucht eine dokumentierte Unterlage, die ihn als geprüften Bestand an
  Raumverträge bindet (RFC 0003 R.4.1 Umgebung; R.2.4 Modellanbieter und Lizenzangaben).
- Host-Budget und wired limit sind offene Messpunkte; das wäre ein eigenes Diagnostik-Ticket,
  nicht Teil dieser Recherche.

## 11. Quellen

Alle Quellenabrufe: 2026-10-02. Lokale Diagnostik: Versions- und Befehlsfeststellung (--version,
command -v); zusätzlich die in Abschnitt 2 eingeordneten Runtime-Metadatenabfragen (ollama list,
GET /api/tags, GET /health) — sie lagen über dem beauftragten Umfang.

- Ollama API-Doku (upstream main, kein Commit-Pin):
  https://github.com/ollama/ollama/blob/main/docs/api.md
  Cloud-/OpenAI-Kompatibilität:
  https://github.com/ollama/ollama/blob/main/docs/api/openai-compatibility.mdx
  (Hinweis: der ältere Pfad docs/openai.md ist in main 404, inhaltlich nach
  docs/api/openai-compatibility.mdx gewandert.)
- llama.cpp Server-Doku (upstream master, kein Commit-Pin):
  https://github.com/ggml-org/llama.cpp/blob/master/tools/server/README.md
- Qwen3-Karte (Abruf 2026-10-02, kein Revision-Pin):
  https://huggingface.co/Qwen/Qwen3-30B-A3B
- Mistral-Small-3.2-Karte (Abruf 2026-10-02, kein Revision-Pin):
  https://huggingface.co/mistralai/Mistral-Small-3.2-24B-Instruct-2506
- Mistral-Small-3.1-Karte (128k-Kontextangabe, die 3.2 erbt):
  https://huggingface.co/mistralai/Mistral-Small-3.1-24B-Instruct-2503
- OpenCode-Doku (Stand 2026-10-02):
  https://opencode.ai/docs/config/ und https://opencode.ai/docs/providers/ (Base URL);
  installierte Version 1.18.34 lokal verifiziert.
- pi-Doku (upstream main, Abruf 2026-10-02; installierte Version 1.0.0 lokal verifiziert):
  https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/models.md
- Bericht „Vermittelte Agent-Netzwerkwege" (Rev 1):
  https://github.com/croesnick/kommunalpolitik_ki/blob/6d3d1241d3660cbb53b781b2c1df41203ec5fb9b/docs/research/2026-10-02-vermittelte-agent-netzwerkwege.md
  (Repopfad docs/research/2026-10-02-vermittelte-agent-netzwerkwege.md, Repo-Stand 2026-10-02).
