# Jev-Alternativen für private deutsche Relevanz-Triage

Stand: 2026-10-02, Europe/Berlin. Diese Notiz ordnet geprüfte Quellen und den lokalen SemIf-Versuch ein. Sie ist keine Installationsanleitung und autorisiert keine weiteren Experimente.

## Ergebnis in Kürze

Kev ist eine ernsthafte direkte Alternative, aber nicht der einzige relevante Ansatz. Für deutsche Ratsnotizen auf einem privaten Mac verdienen auch GLiClass und GLiNER2.5-multi-Decide einen Vergleich. SetFit beantwortet eine andere Frage: Wie gut lässt sich eine feste Klassifikation mit eigenen gelabelten Beispielen trainieren?

GitHub-Popularität, Benchmark-Führung und Eignung für diesen Einsatz sind verschiedene Befunde. Laya hat hier die meisten Repository-Sterne. Cygnet und Winnow führen gemeinsam einen bestimmten Benchmark. Für deutsche lokale Triage belegt keiner dieser Befunde allein die beste Wahl. Unsere eigene Priorisierung folgt weiter unten, getrennt von den Quellenbefunden.

## Kategorien und Repository-Sterne

Die Tabelle zählt Repositories, nicht Modellvarianten, Downloads oder Empfehlungen. A bezeichnet den GitHub-GraphQL-Snapshot vom 2026-10-02 um 12:00:11 CEST, B um 12:03:52 und C um 12:11:31. Alle aufgeführten Repositories waren nicht archiviert. Die Lizenzspalte betrifft den Code; Modellgewichte können andere Bedingungen haben.

| Repository | Kategorie | Sterne | Code-Lizenz | Snapshot |
|---|---|---:|---|---|
| [Laya](https://github.com/NandhaKishorM/laya) | Direktes Modell | 30.004 | Apache-2.0 | A |
| [Kev](https://github.com/jaredpalmer/kev) | Direktes Modell | 8.256 | Apache-2.0 | A |
| [SemIf](https://github.com/TheoLeeCJ/SemIf-OpenJev) | LLM-basierter Bewertungsansatz | 4.659 | MIT | A |
| [AnyJev](https://github.com/nokia-applied-research/AnyJev) | Wrapper und Anpassungsverfahren | 1.008 | Apache-2.0 | A |
| [laya-mlx](https://github.com/mizorewww/laya-mlx) | Laufzeit-Port desselben Modells | 6.702 | Apache-2.0 | B |
| [Decider](https://github.com/Mapika/decider) | Direkte Optionsbewertung | 1.033 | Apache-2.0 | B |
| [Von](https://github.com/wfzyx/von) | Direkter CPU-Klassifikator | 812 | Apache-2.0 | B |
| [NanoJev](https://github.com/TianyuCodings/NanoJev) | Direktes Modell | 2.474 | MIT | B |
| [Jevos](https://github.com/feder-cr/jev) | Modell und C++-Laufzeit | 1.175 | MIT | B |
| [GLiClass](https://github.com/Knowledgator/GLiClass) | Klassifikationsbibliothek | 549 | Apache-2.0 | B |
| [GLiNER2](https://github.com/fastino-ai/GLiNER2) | Modellfamilie und Bibliothek | 2.290 | Apache-2.0 | B |
| [SetFit](https://github.com/huggingface/setfit) | Few-shot-Trainingsverfahren | 2.827 | Apache-2.0 | B |
| [cygnet-recipe](https://github.com/blockbrain-ai/cygnet-recipe) | Bewertungsrezept und Serveradapter | 25 | MIT | C |
| [winnow-inference](https://github.com/EldanRing/winnow-inference) | Inferenzserver | 18 | MIT | C |

Repository-Alter erschwert den Vergleich. Kev, SemIf, Laya und AnyJev wurden zwischen dem 16. und 21. September 2026 angelegt. SetFit stammt aus 2022, GLiClass aus 2024. Das Repository-Datum beweist weder das Alter eines Modells noch seine Qualität.

### Direkte Modelle und Bewertungsverfahren

[Laya](https://github.com/NandhaKishorM/laya) verwendet einen Encoder mit Entscheidungsköpfen und RLCD und bietet einen multilingualen Checkpoint. [laya-mlx](https://github.com/mizorewww/laya-mlx) führt dasselbe Modell nativ mit MLX aus. Der Port ist kein eigenständiger Qualitätsnachweis; wir haben ihn nicht lokal getestet.

[SemIf](https://github.com/TheoLeeCJ/SemIf-OpenJev) liest Optionslogits aus einem eingefrorenen LLM aus. Das Projekt dokumentiert CPU mit GGUF sowie MPS- und MLX-Pfade. SemIf hieß früher OpenJev. Es ist nicht das andere Projekt `razorback16/openjev`; ältere Benchmark-Verweise können noch auf `TheoLeeCJ/openjev` zeigen.

Die [Kev-4B-Modellkarte](https://huggingface.co/jaredpalmer/kev-4b) beschreibt LoRA und einen Pointer-Head auf Qwen3.5-4B-Base. Der Server bietet das TypeSafe-kompatible `POST /v1/systemone` über CUDA oder automatisch gewähltes MLX. Das Basismodell benötigt ungefähr 8 bis 9 GB. Englisch ist der dokumentierte Sprachumfang; andere Sprachen liegen außerhalb dieses Umfangs. Das beweist kein deutsches Versagen, lässt deutsche Eignung aber offen. Eigenes sprachbezogenes Fine-Tuning ist dokumentiert. Einen CPU-GGUF-Pfad haben die geprüften Quellen nicht belegt.

Kev veröffentlicht Prüfsummen für Testsuiten und CI-Prüfungen. Das macht die vom Hersteller ausgeführten Tests nachvollziehbarer, ersetzt jedoch keine unabhängige Prüfung. Die Temperatur 2,41 stammt aus Entwicklungsdaten des Trainingskorpus. Die Karte warnt vor Domänenwechseln und notwendiger workloadbezogener Anpassung. Daraus folgt keine Kalibrierungsgarantie für deutsche Ratsnotizen.

[AnyJev](https://github.com/nokia-applied-research/AnyJev) adaptiert beliebige LLMs in drei Stufen. L0 nutzt gemittelte Optionsrotationen und Label-Prior-Korrektur ohne Labels. L1 passt eine Temperatur mit etwa 100 bis 500 Labels je Frage an. L2 berechnet einen Kopf mit etwa 100 bis 300 Labels je Modell und Frage. Diese Anpassung ist kein allgemeiner Transfer auf neue Fragen. Transformers und vLLM sind dokumentiert, ein spezifischer MLX- oder llama.cpp-CPU-Pfad ist nicht verifiziert. Der [technische Bericht](https://arxiv.org/abs/2610.00831) vom 30. September ist frühe Arbeit, kein SOTA-Beweis durch institutionelle Zugehörigkeit.

Die übrigen direkten Projekte ändern unsere erste Auswahl nicht. [Decider](https://github.com/Mapika/decider) dokumentiert GGUF auf CPU, nennt aber ausdrücklich nur Englisch. [Von](https://github.com/wfzyx/von) nennt ebenfalls Englisch und verwendet OpenVINO auf CPU. [NanoJev](https://github.com/TianyuCodings/NanoJev) zeigt CUDA und Spiele-Benchmarks, keine deutsche Triage. [Jevos](https://github.com/feder-cr/jev) bietet C++-CPU-Inferenz und macOS-arm64-Releases mit einem frühen Score-Vertrag. Diese Befunde rechtfertigen keine deutsche Qualitätsrangfolge.

### Kleinere Klassifikatoren und feste Taxonomien

[GLiClass-multilang-mini](https://huggingface.co/knowledgator/gliclass-multilang-mini) hat ungefähr 288 Millionen Parameter und nennt Deutsch unter 20 unterstützten Sprachen. Labels, Beschreibungen und Aufgabenprompts lassen sich zur Laufzeit vorgeben. Die Bibliothek unterstützt Beispiele im Kontext und Training. Sprachunterstützung ist kein Nachweis hoher deutscher Triage-Genauigkeit; Beispiele im Kontext sind keine Wahrscheinlichkeitskalibrierung. Der [GLiClass-Preprint](https://arxiv.org/abs/2508.07662) ist verfügbar, sein Peer-Review-Status wurde nicht verifiziert.

[GLiNER2.5-multi-Decide](https://huggingface.co/fastino/GLiNER2.5-multi-Decide) ist eine direkte Entscheidungsvariante mit 287 Millionen Parametern auf mDeBERTa-v3-base. Sie bewertet frei vorgegebene Labels, Beschreibungen und Fragen mit mehreren Köpfen in einem Forward-Pass, ohne Textgenerierung, auf CPU oder GPU. Die Karte beschreibt Mehrsprachigkeit, aber keine deutsche Triage-Evaluation. Das ältere [gliner2-multi-v1](https://huggingface.co/fastino/gliner2-multi-v1) nennt Deutsch ausdrücklich; diese Eigenschaft darf nicht ungeprüft auf alle Varianten übertragen werden.

Der englische Autorenbenchmark von multi-Decide umfasst 17 Domänen mit jeweils 300 zurückgehaltenen Beispielen. Er berichtet 56,7 Prozent für das Modell, 56,4 für SemIf mit Qwen4B und 46,6 für LayaRouter. Das ist keine unabhängig bestätigte Überlegenheit und kein deutscher Vergleich. Die 2.290 Sterne gehören zur Bibliothek, nicht zu diesem Checkpoint. Auch der [GLiNER2-Artikel](https://arxiv.org/abs/2507.18546) ist hier nur als Preprint belegt.

[SetFit](https://huggingface.co/docs/setfit) trainiert kleine Klassifikatoren auf Sentence-Transformers und erlaubt multilinguale Encoder. Neue Labels einer festen Taxonomie benötigen erneutes Training. Die oft genannten acht Beispiele je Klasse beziehen sich auf einen konkreten Customer-Reviews-Sentiment-Vergleich mit RoBERTa-large. Sie belegen nicht, dass diese Datenmenge allgemein genügt. Der [SetFit-Artikel](https://arxiv.org/abs/2209.11055) beschreibt das Verfahren. Als weitere Referenz eignet sich [mDeBERTa-XNLI](https://huggingface.co/MoritzLaurer/mDeBERTa-v3-base-xnli-multilingual-nli-2mil7). Seine deutsche XNLI-Accuracy von 0,824 misst Entailment auf 5.010 Testbeispielen, nicht Ratsnotiz-Relevanz.

## Was die aktuelle Benchmark-Spitze belegt

[BenchmarkHeaven](https://benchmarkheaven.com/jev-models) führt mit dem [JevBench-Kit](https://github.com/fstandhartinger/jevbench) einen Drittanbieterbenchmark durch. Das ist kein TypeSafe-eigener Benchmark, aber auch kein universell unabhängiges Audit. Die [API-Version v1.5.4](https://benchmarkheaven.com/api/jevbench/v1.5.4) umfasst 1.624 Entscheidungen: 904 offene und 720 versiegelte. Für die versiegelten Fälle sind nur Aggregate öffentlich. Kosten sind geschätzt, Hardware und Latenzbedingungen unterscheiden sich; deutsche Triage wurde nicht nachgewiesen.

Der offizielle Composite A verwendet das harmonische Mittel von vier Achsen mit jeweils 25 Prozent Gewicht und einer Intelligence-Untergrenze. Cygnet erreicht 73,701267, Winnow-12B-Q8 73,233103 und Jev 1.13.0 72,132929. Der Benchmark markiert Cygnet und Winnow als statistisch gleichauf liegende gemeinsame Spitzenreiter. Eine sichere Aussage, Cygnet schlage Winnow, wäre falsch. Die getrennte Capability-Anzeige mittelt Intelligence und Calibration und nennt Jev 80,0, Winnow 79,3 und Cygnet 79,0. Unterschiedliche Metriken erklären die Reihenfolge. Alte v1.3-Plätze wie SemIf auf Rang 2 und Laya auf Rang 33 sind nicht aktuell übertragbar.

[Cygnet](https://github.com/blockbrain-ai/cygnet-recipe) ist ein Rezept mit eingefrorenem Gemma4-12B und vLLM-Adapter, kein eigener trainierter Gewichtscheckpoint. Eine Chat-Anfrage bewertet maskierte Buchstabenoptionen über Logprobs. Temperatur 3,4 wurde auf 241 selbst erzeugten Fällen angepasst. GPU ist dokumentiert, Apple-CPU-Eignung und Deutsch sind offen. MIT für den Code ersetzt nicht die Bedingungen der Gemma-Gewichte.

[Winnow-12B](https://huggingface.co/EldanRing/Winnow-12B) verbindet LoRA mit Gemma4-12B und veröffentlicht zusammengeführte Gewichte. GGUF Q8 benötigt ungefähr 11,8 GiB, BF16 ungefähr 22,2 GiB. Der Trainingsdatensatz ist privat. Der [Server](https://github.com/EldanRing/winnow-inference) nutzt llama.cpp; ein deutscher Benchmark fehlt. Temperatur 1,0 und Entropie-Konfidenz belegen keine separat angepasste Kalibrierung. Die 18 Sterne zählen den Server, nicht das Hugging-Face-Artefakt. Der [Decision Index](https://github.com/apolinario/decision-index) v0.2.1 verwendet dagegen 38 Datensätze und Zufallskorrektur. Seine Werte sind nicht mit Composite A gleichzusetzen.

## Tatsächliche Integration statt Empfehlungszahlen

[Ollaya](https://github.com/ollaya-dev/ollaya) und [kev-decision-mcp](https://github.com/HappyMonkeyAI/kev-decision-mcp) binden Kev ein. Für GLiNER2 existieren der [Swift-MLX-Port von MacPaw](https://github.com/MacPaw/Gliner2Swift) und [gliner2-mcp](https://github.com/mrorigo/gliner2-mcp). Das belegt Familienintegration, nicht Funktion der neuen Decide-Variante oder einen Produktionseinsatz. [MLflow](https://github.com/mlflow/mlflow) integriert SetFit im Transformers-Modul. [zerolinc-benchmark](https://github.com/CristhianKapelinski/zerolinc-benchmark) untersucht GLiClass außerhalb des Maintainerprojekts, belegt aber keinen deutschen Vergleich.

Wir haben Existenz und Quellenangaben dieser Integrationen geprüft, nicht die Ports ausgeführt. Eine belastbare Zahl unabhängiger Empfehlungen liegt nicht vor. Ein Awesome-List-Eintrag ist keine Qualitätsprüfung. Routing- und Serving-Infrastruktur ist außerdem eine andere Kategorie als ein Entscheidungsmodell.

## Eigene Priorisierung und Grenzen

SemIf bleibt unsere empirische Referenz. Der private [SemIf-Labbook-Eintrag](file:///Users/crn/labbooks/2026-10-02-semif-pilot/LABBOOK.md) dokumentiert Commit `23cf1f3`, Qwen3.5-4B Q4_K_M auf CPU und drei identische Läufe mit jeweils 12 von 12 korrekten Fällen. Der Forward-Median beträgt 2,54 Sekunden. ID- und Optionsreihenfolge-Kontrollen bestanden. Der [Laya-Labbook-Eintrag](file:///Users/crn/labbooks/2026-09-24-laya-pilot/LABBOOK.md) dokumentiert für das gepinnte Laya 0.3.20 multilingual 8 von 12, davon 2 von 6 relevanten und 6 von 6 irrelevanten Fällen. Alte Temperaturkonfigurationen gelten nicht automatisch für heutige Laya-Versionen.

Das sind zwölf synthetische Titel, nicht 36 unabhängige Beispiele oder ein externer Benchmark. Die Labbooks und Datensätze sind private lokale Aufzeichnungen, keine geteilten Repo-Artefakte. SemIf-p ist ein bedingter, unkalibrierter Optionsscore, keine Wahrscheinlichkeit eines richtigen Urteils.

Als nächste kleinere Vergleichskandidaten priorisieren wir GLiClass-multilang-mini und GLiNER2.5-multi-Decide. Kev verdient ebenfalls einen deutschen Versuch, seine deutsche Eignung ist aber nicht belegt. Keiner dieser Kandidaten ist damit für unseren Produktionseinsatz validiert. SetFit passt, wenn eine feste Taxonomie und eigenes Training akzeptiert werden. Winnow und Cygnet liefern Benchmark-Referenzen, sind schwerer und im deutschen lokalen Einsatz ungeprüft.

Ein neues deutsches Goldset mit zunächst 30 bis 50 Fällen und separatem Holdout wäre angemessener als weitere Aussagen aus denselben zwölf Titeln. Das verspricht keine statistische Sicherheit. Menschliches GO und deterministische Berechtigungen bleiben außerhalb der Klassifikatoren. Diese Recherche installiert nichts und ändert keinen RFC.

## Quellenmethode und reproduzierbare Sternzählung

Die verlinkten Primärquellen und Sternzahlen stammen aus abgeschlossener Recherche mit Gegenprüfung der tragenden Aussagen. Sternzahlen wurden über die [GitHub-GraphQL-API](https://api.github.com/graphql) zu den oben genannten Zeiten erfasst. Eine spätere REST-Abfrage kann abweichen:

```sh
gh api repos/jaredpalmer/kev --jq .stargazers_count
```

Ersetze `jaredpalmer/kev` im Befehl durch das gewünschte Repository. Die Abfrage misst den neuen Abrufzeitpunkt, nicht rückwirkend diesen Snapshot. Modellkarten und READMEs enthalten überwiegend Autorenangaben; unbestätigte Sprach-, Kalibrierungs- und Hardwareaussagen bleiben entsprechend begrenzt.
