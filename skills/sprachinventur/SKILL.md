---
name: sprachinventur
description: Fachbegriffe des Repos inventieren, mit Quellen belegen, kanonisieren und uneinheitliche Begriffe ersetzen. Nutze diesen Skill immer, wenn über einen Fachbegriff entschieden werden soll („Ist X etabliert?“, „Gibt es das Wort überhaupt?“, „Deutsch oder englisch lassen?“), ein deutsches Kompositum für ein technisches Konzept geprägt werden soll, ein neues deutsches Dokument Fachbegriffe einführt, Schreibdrift oder widersprüchliche Begriffe zwischen Dokumenten auffallen, oder eine Sprachinventur, ein Einzelverdikt oder ein Ersetzungs-Sweep ansteht. Auch vor dem Commit neuer deutscher Fachtexte mit unbekannten Begriffen.
---

# Sprachinventur

## Zweck

Dieses Repo schreibt deutsche Fachtexte über überwiegend englischsprachige Technik. Die Sprachregelung in AGENTS.md entscheidet das Prinzip: Etablierte englische Begriffe bleiben englisch; deutsch nur, wo ein etablierter deutscher Begriff existiert oder noch kein etablierter englischer Begriff vorhanden ist. Dieser Skill ist der ausführbare Prozess dahinter: Begriffe finden, belegen, entscheiden, ersetzen, pflegen.

In [docs/sprachinventur.md](../../docs/sprachinventur.md) stehen die bereits gefällten Entscheidungen. Vor jeder neuen Entscheidung dort nachschlagen; nichts wird doppelt entschieden. Definitionen trägt GLOSSARY.md; die Inventur klassifiziert und verweist dorthin, ohne sie zu duplizieren.

## Das Verfahren

1. **Korpus festlegen.** Welche Dateien? Aktive Dokumente zählen. Code-Bezeichner (Funktionen, Module, CLI-Flags, MCP-Parameter) sind außen vor. Historische Dokumente (RFC0000, RFC0001) werden nur inventiert, nie korrigiert. Englischsprachige Dokumente und das Inventur-Dokument selbst sind Grenzdateien.
2. **Extraktion.** Kandidaten in fünf Kategorien sammeln: K1 Fachbegriff deutsch (etabliert wirkend), K2 englischer Term im deutschen Text, K3 Denglish-Mischform, K4 Eigenprägungs-Verdacht (deutsches Kompositum als vermutete Pseudo-Übersetzung), K5 wiederkehrende feste Phrase.
3. **Verifikation mit Quellenpflicht.** Jede last-tragende Klassifikation braucht einen Beleg: wörtliches Zitat, Quelle, URL, Abrufdatum — oder einen dokumentierten Negativbefund. Ohne Beleg: Status OFFEN.
4. **Entscheidung.** Kanonische Form festlegen und in docs/sprachinventur.md eintragen. Ersetzungs-Sweeps im Korpus erst nach GO der nutzenden Person.
5. **Pflege.** Neue Begriffe wandern bei ihrer Ersteinführung direkt ins Inventur-Dokument — analog zur Fett-Konvention in RFC0003 (Begriff bei erster Einführung fett markieren und definieren).

Für ein Einzelverdikt („Ist dieser Begriff okay?“) genügen die Schritte 3 und 4. Einen Korpus braucht es dafür nicht.

## Statuswerte

| Status | Bedeutung | Folge |
|---|---|---|
| ETABLIERT_DE | Es gibt einen etablierten deutschen Fachbegriff für das Konzept | deutsch verwenden |
| NUR_ENGLISCH | Nur der englische Begriff ist fachlich etabliert | englisch lassen; keine deutschen Komposita prägen |
| EIGENE_PRÄGUNG_OK | Kein Begriff etabliert (weder deutsch noch englisch) | Neuprägung legitim; bei Ersteinführung definieren |
| FEHLFORM | Keine lexikografische Basis; existiert höchstens als Versehen | ersetzen |
| OFFEN | Beleglage unklar | klären, bevor der Begriff last-tragend wird |

## Verifikationsquellen

- **Deutsche Allgemeinwörter:** Duden und DWDS. Die Positivkontrolle muss mitkommen: Wenn ein verwandtes, sicher belegtes Wort im selben Werkzeug keinen Treffer liefert, war die Suche kaputt, nicht das Wort.
- **Fachbegriffe:** deutschsprachige Fachglossen und Hersteller-Dokumentation (ISTQB, BSI, Microsoft, Obsidian, GitHub, heise, git-scm.de, IBM). Die deutsche Doku eines Herstellers ist ein starker Beleg. Schwankt sie selbst zwischen zwei Formen, ist das ein Beleg für NUR_ENGLISCH.
- **Emergente Begriffe der KI-Sicherheit:** englische Paper und Spezifikationen zitieren; eine deutsche Form ohne jeden Beleg ist Eigenprägungs-Verdacht, keine Übersetzung.
- **Normtexte:** Ein Normtext, der selbst beide Formen benutzt (Beispiel ISO/TS 23494 mit „Provenanz-Modell“ und „Provenienz“), belegt keine der beiden.

## Regeln

- **Quellenpflicht gilt auch für Widerlegung.** Ein Negativbefund ist selbst eine last-tragende Behauptung. Jede Widerlegung mit einem unabhängigen Werkzeug gegenprüfen, das nachweislich dieselbe Datei durchsucht (das Grep-Werkzeug durchsuchte RFC0000 schlicht nicht; die Widerlegung war ein Artefakt).
- **Korrupte Darstellung ist nicht widerlegt.** Garbles in einer Lane-Ausgabe bedeuten Unlesbarkeit, nicht Falschheit. Inhaltsangaben aus Garble-Ausgaben mit einem sauberen Werkzeug nachweisen, bevor sie verworfen oder übernommen werden.
- **Sweeps nur nach GO.** Doppelverifikation: die ausführende Lane zählt, der Orchestrator zählt mit einem unabhängigen Werkzeug nach. Die Schlusszählung („X verblieben: null“) wird dokumentiert.
- **Genus und Kasus mitdenken.** Jede Kanonisierung legt das Genus fest (der Payload), und der Sweep gleicht Artikel und Kasusendungen an.
- **Wortfelder trennen.** Quellenpflicht und Quellenbindung sind verschiedene Konzepte; Session (Harness-Kontext) und Sitzung (Ratsversammlung) sind verschiedene Konzepte. Ein Begriff, der zwei Konzepte deckt, ist eine Falle — im Inventur-Dokument mit Verweis auf GLOSSARY.md scharf machen.
- **Phrasen bewusst kanonisieren.** Wörtliche Kopien einer Formel zwischen Skills sind kein Beleg für getrennte Konzepte. Eine bewusst festgelegte Variante ist sauberer als driftende Parallelformen.
- **Grenzdateien unberührt lassen:** historische RFCs, englischsprachige Dokumente, das Inventur-Dokument selbst. GLOSSARY.md nur nach ausdrücklichem GO.

## Nach dem Sweep

`mix format` muss grün sein, die Schlusszählung steht im Inventur-Dokument, und neue deutsche Textpassagen gehen vor dem Commit durch den humanizer-de-Pass (Repo-Regel). Beleg-URLs vor Veröffentlichung stichprobenartig prüfen.
