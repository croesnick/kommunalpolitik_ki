# Benchmark: sitzungsvorbereitung

Gemessen am 30. Oktober 2026 gegen das Zielmodell der komki-Instanz. Alle Zahlen sind Rohzählungen über die gelaufenen Läufe; nichts davon „belegt“ einen Nutzen für sich allein — gezählt wird, was zählbar ist. Fälle, Fixtures und Bewerter stehen versioniert in [`evals/`](evals/) (Suite-Stand: `cb707d15`); jede Änderung an einem Kriterium setzt die Vergleichsreihe zurück und gehört in denselben Commit.

## Rahmen

| Feld | Wert |
|---|---|
| Modell | Gemma 4 26B-A4B-it (llama.cpp, Zielmodell der komki-Instanz) |
| GGUF | `gemma-4-26B-A4B-it-UD-Q4_K_XL.gguf` · sha256 `ef728c8e0c337fd1…` |
| Sampling (Server-Defaults, pro Request nicht überschrieben) | temp 1 · top-p 0.95 · top-k 64 · min-p 0.05 · repeat-penalty 1 · seed zufällig |
| llama-server | llama.cpp 0.7.0 · port 49524 · auth erforderlich |
| pi · Node | pi 1.4.0 · v24.22.1 |
| Kontext · maxTokens | 131072 · 16384 |
| Läufe pro Arm | 5 |
| Arme je Runde abwechselnd | ja (Lauf 1 aller Arme, dann Lauf 2, …) |
| Fremdlast (serverRequestCountMismatch) | 0/55 Läufe |
| Richter für llm-Kriterien | dasselbe Modell (Gemma 4 26B) über denselben llama-server, Server-Defaults, Urteil PASS/FAIL in Zeile 1 |

## Arme (Verhaltensfälle)

| Arm | Skill-Fassung | Zeilen | sha256 (Inhalt) | Herkunft |
|---|---|---|---|---|
| **ohne Skill** | kein Skill im Kontext (--no-skills, kein Anhang) | – | `–` | – |
| **vorige Fassung** | SKILL.md (834 Zeilen) | 834 | `4852e15ae01d4e9aed9c747d558a3d1eb0fcb3782b4b29f99b55c475786eb915` | git 9c50fa1 |
| **aktuelle Fassung** | SKILL.md (236 Zeilen) | 236 | `f84541999200b757e26564a71d4b9cf3a5ffe107436778d0c1967778e15f62ae` | Arbeitskopie = HEAD cb707d15 |

## Fall: formaler-top (verhalten)

Negativverhalten innerhalb des Skills: Ein formaler TOP (Protokollgenehmigung) bekommt genau eine Zeile — keine Lückenliste, kein »Angabe fehlt«, keine Checklisten-Felder. Schützt davor, dass die Checkliste des Skills mechanisch auf jeden TOP angewendet wird.

> Prompt: „Bereite TOP 1 als Abschnitt für meine Sitzungsmappe auf. Die Vorlage liegt als top-1-protokoll.md im aktuellen Verzeichnis.“
> Quelle des Falls: Issue #292 Kommentar »Erste Fälle«: »Eine Fixture mit formalem TOP fehlt noch. Sie wäre der Negativfall«
> Fixtures (synthetisch): `fixtures/top-1-protokoll.md`

| Kriterium (Bewerter) | ohne Skill | vorige Fassung | aktuelle Fassung |
|---|---|---|---|
| **formal-top-kompakt** (llm) | 0/5 | 0/5 | 5/5 |
| **keine-lueckenliste** (enthaelt-nicht) | 5/5 | 1/5 | 5/5 |
| **protokoll-genannt** (enthaelt) | 3/5 | 5/5 | 5/5 |
| **vorlage-gelesen** (tool-call) | 5/5 | 5/5 | 5/5 |

- **ohne Skill** — Median-Wandzeit: 107,8 s · Median Prompt-Tokens: 62411 · Median Completion-Tokens: 4267 · Läufe mit Timeout/Fehler: 2/5 · ungültige Tool-Calls: 0
  Fehlkriterien: formal-top-kompakt fehlt 5/5 · protokoll-genannt fehlt 2/5
- **vorige Fassung** — Median-Wandzeit: 69,1 s · Median Prompt-Tokens: 24195 · Median Completion-Tokens: 1275 · Läufe mit Timeout/Fehler: 0/5 · ungültige Tool-Calls: 0
  Fehlkriterien: formal-top-kompakt fehlt 5/5 · keine-lueckenliste fehlt 4/5
- **aktuelle Fassung** — Median-Wandzeit: 50,5 s · Median Prompt-Tokens: 8860 · Median Completion-Tokens: 1797 · Läufe mit Timeout/Fehler: 0/5 · ungültige Tool-Calls: 0
  Fehlkriterien: keine

Kriterien des Falls:
- **formal-top-kompakt** (llm, `evals/cases/formaler-top/bewerter/formal-top-kompakt.md`): PASS wenn die Antwort den formalen TOP in höchstens zwei Sätzen abhandelt und dabei keine Checklisten-Felder auflistet (keine Kosten-, Finanzierungs- oder Fristen-Zeile, kein Block »Was die Vorlage nicht sagt«, keine Fragen für die Fraktion).
FAIL wenn die Antwort länger als zwei Sätze ist oder für diesen formalen TOP Checklisten-Felder, Lücken oder offene Punkte aufführt.
- **keine-lueckenliste** (enthaelt-nicht, `evals/cases/formaler-top/bewerter/keine-lueckenliste.md`): Ein formaler TOP (Protokollgenehmigung, Bekanntgaben) bekommt laut Skill
genau eine Zeile. Diese Signale einer Lückenliste oder
Checklisten-Behandlung dürfen im Abschnitt nicht vorkommen — sonst
überträgt das Modell die Checkliste mechanisch auf jeden TOP.
- **protokoll-genannt** (enthaelt, `evals/cases/formaler-top/bewerter/protokoll-genannt.md`): Der formale TOP muss überhaupt benannt werden: Protokoll der Sitzung vom
15.10.2026, Genehmigung.
- **vorlage-gelesen** (tool-call, `evals/cases/formaler-top/bewerter/vorlage-gelesen.md`): Der Abschnitt muss aus der gelesenen Vorlage stammen.

## Fall: kurzprompt-top3 (verhalten)

Regressionsfall aus #158: derselbe TOP unter knappem Prompt (»höchstens fünf Sätze«). Ohne Skill fehlte der Eigenanteil in jedem Lauf; das Kriterium hier verlangt die Zahl, das Wort »Eigenanteil« allein genügt nicht (Lehre aus #158: ein zu lasches K6 machte aus 2/5 versehentlich 5/5).

> Prompt: „Lies die Datei top-3-anhoerung.md im aktuellen Verzeichnis und fasse TOP 3 für die Sitzungsvorbereitung in höchstens fünf Sätzen zusammen. Nenne Gremium, Sitzungsdatum, Kostenschätzung und Beschlussvorschlag.“
> Quelle des Falls: #158, Aufgabe 1 und TOP-Benchmark (run-top-bench.mjs, K1–K8)
> Fixtures (synthetisch): `fixtures/top-3-anhoerung.md`

| Kriterium (Bewerter) | ohne Skill | vorige Fassung | aktuelle Fassung |
|---|---|---|---|
| **k1-gremium** (enthaelt) | 5/5 | 5/5 | 5/5 |
| **k2-sitzungsdatum** (enthaelt) | 5/5 | 5/5 | 5/5 |
| **k3-vorhaben** (enthaelt) | 5/5 | 5/5 | 5/5 |
| **k4-anliegen** (enthaelt) | 5/5 | 5/5 | 5/5 |
| **k5-gesamtkosten** (enthaelt) | 5/5 | 5/5 | 5/5 |
| **k6-finanzierung** (enthaelt) | 0/5 | 0/5 | 5/5 |
| **k7-beschlussvorschlag** (enthaelt) | 5/5 | 5/5 | 5/5 |
| **k8-zahlen** (zahlen) | 5/5 | 5/5 | 5/5 |
| **kein-erfundener-link** (enthaelt-nicht) | 5/5 | 5/5 | 5/5 |
| **vorlage-gelesen** (tool-call) | 5/5 | 5/5 | 5/5 |

- **ohne Skill** — Median-Wandzeit: 22,6 s · Median Prompt-Tokens: 2217 · Median Completion-Tokens: 819 · Läufe mit Timeout/Fehler: 0/5 · ungültige Tool-Calls: 0
  Fehlkriterien: k6-finanzierung fehlt 5/5
- **vorige Fassung** — Median-Wandzeit: 25,1 s · Median Prompt-Tokens: 24259 · Median Completion-Tokens: 730 · Läufe mit Timeout/Fehler: 0/5 · ungültige Tool-Calls: 0
  Fehlkriterien: k6-finanzierung fehlt 5/5
- **aktuelle Fassung** — Median-Wandzeit: 26,2 s · Median Prompt-Tokens: 8879 · Median Completion-Tokens: 922 · Läufe mit Timeout/Fehler: 0/5 · ungültige Tool-Calls: 0
  Fehlkriterien: keine

Kriterien des Falls:
- **k1-gremium** (enthaelt, `evals/cases/kurzprompt-top3/bewerter/k1-gremium.md`): K1 aus #158: Gremium benannt.
- **k2-sitzungsdatum** (enthaelt, `evals/cases/kurzprompt-top3/bewerter/k2-sitzungsdatum.md`): K2 aus #158: Sitzungsdatum benannt.
- **k3-vorhaben** (enthaelt, `evals/cases/kurzprompt-top3/bewerter/k3-vorhaben.md`): K3 aus #158: Vorhaben mit Namen, nicht »das Vorhaben«.
- **k4-anliegen** (enthaelt, `evals/cases/kurzprompt-top3/bewerter/k4-anliegen.md`): K4 aus #158: das Anliegen ist erkennbar (konkrete Maßnahmen). Das weiche
K4 der Nachmessung in #158 (»Umgestaltung« zählte nicht) wertete einen
Lauf, der das Anliegen nur als Umgestaltung benannte, als unvollständig —
hier zählt jede Maßnahme.
- **k5-gesamtkosten** (enthaelt, `evals/cases/kurzprompt-top3/bewerter/k5-gesamtkosten.md`): K5 aus #158: Gesamtkosten benannt.
- **k6-finanzierung** (enthaelt, `evals/cases/kurzprompt-top3/bewerter/k6-finanzierung.md`): K6 aus #158, streng (Nachmessung): Finanzierungsstruktur — die Zahl
80 000 muss fallen. Das Wort »Eigenanteil« allein genügt nicht; das
lasche K6 des ersten Benchmarks machte aus 2/5 versehentlich 5/5.
- **k7-beschlussvorschlag** (enthaelt, `evals/cases/kurzprompt-top3/bewerter/k7-beschlussvorschlag.md`): K7 aus #158: Beschlussvorschlag im Wortlaut oder mit allen Komponenten —
mindestens zwei der drei Komponenten (Zustimmung, Meldung zur
Haushaltsplanung 2027, Ergänzungsantrag Beleuchtung).
- **k8-zahlen** (zahlen, `evals/cases/kurzprompt-top3/bewerter/k8-zahlen.md`): K8 aus #158: keine erfundenen Zahlen; abgeleitete Zahlen (Summe oder
Differenz aus Vorlage-Zahlen, z. B. Förderanteil 160 000) sind toleriert,
werden protokolliert und müssen als abgeleitet gekennzeichnet sein.
- **kein-erfundener-link** (enthaelt-nicht, `evals/cases/kurzprompt-top3/bewerter/kein-erfundener-link.md`): Zusatzkriterium über K1–K8 hinaus: Die Fixture enthält weder Link noch
Abrufdatum — jede URL und jedes Abrufdatum in der Antwort ist erfunden.
- **vorlage-gelesen** (tool-call, `evals/cases/kurzprompt-top3/bewerter/vorlage-gelesen.md`): Die Zusammenfassung muss aus der gelesenen Datei stammen.

## Fall: negativ-antrag (negativ)

Negativfall: Die Description darf nicht greifen. Der Prompt verlangt einen Stadtratsantrag (Bahnhofstraße als Thema ist bewusst eine Falle) — laut Description der Sache von antrag_generieren, nicht der Sitzungsmappe: »Anträge … sind NICHT Teil der Mappe«. Gemessen wird, dass die SKILL.md des Zielskills nicht geladen wird.

> Prompt: „Schreib mir einen Stadtratsantrag dazu: Die Anwohner der Bahnhofstraße leiden unter dem nächtlichen Lieferverkehr. Der Antrag soll verlangen, dass Lieferungen in der Bahnhofstraße nur zwischen 6 und 9 Uhr erlaubt sind.“
> Quelle des Falls: Issue #292: »mindestens ein Negativfall je Skill (die description … darf nicht greifen)«
> Arm: echte Skill-Auswahl über pis `--skill`-Mechanismus — alle 11 Skills registriert, kein Anhängen an den System-Prompt. Gemessen wird, ob der Skill per `read` geladen wird (Trigger) bzw. nicht geladen wird (Negativ).

| Kriterium (Bewerter) | aktuelle Fassung |
|---|---|
| **skill-nicht-gelesen** (tool-call) | 5/5 |

- **aktuelle Fassung** — Median-Wandzeit: 61 s · Median Prompt-Tokens: 8206 · Median Completion-Tokens: 2312 · Läufe mit Timeout/Fehler: 0/5 · ungültige Tool-Calls: 0
  Fehlkriterien: keine

Auffälligkeiten (automatisch gesammelt):
- Ziel-Skill gelesen: 0/5 Läufe (erwartet 0)

Kriterien des Falls:
- **skill-nicht-gelesen** (tool-call, `evals/cases/negativ-antrag/bewerter/skill-nicht-gelesen.md`): Das Kernkriterium des Negativfalls: Der Prompt verlangt einen Antrag —
laut Description der Sache von antrag_generieren (»Anträge, Positionen und
Änderungsanträge sind NICHT Teil der Mappe«). Die SKILL.md des
sitzungsvorbereitung-Skills darf in keinem Lauf geladen werden. Bahnhofstraße
im Prompt ist eine bewusste Stichwort-Falle.

## Fall: sitzungsmappe-top3 (verhalten)

Kernfall aus #158: einen inhaltlichen TOP als Abschnitt für die Sitzungsmappe aufbereiten. Der Skill verlangt Finanzierungszahlen (Eigenanteil als Zahl), benannte Fristen und einen Block „Was die Vorlage nicht sagt“. Die Fixture enthält weder Link noch Abrufdatum — jede URL und jedes Abrufdatum in der Antwort ist erfunden.

> Prompt: „Bereite TOP 3 als Abschnitt für meine Sitzungsmappe auf. Die Vorlage liegt als top-3-anhoerung.md im aktuellen Verzeichnis.“
> Quelle des Falls: #158, Nachmessung 2 (»Kritisches Lesen, Fristen, Quellen«); Issue #292 Kommentar »Erste Fälle«
> Fixtures (synthetisch): `fixtures/top-3-anhoerung.md`

| Kriterium (Bewerter) | ohne Skill | vorige Fassung | aktuelle Fassung |
|---|---|---|---|
| **barrierefreiheit-offen** (enthaelt) | 0/5 | 5/5 | 5/5 |
| **beleuchtung-offen** (enthaelt) | 0/5 | 5/5 | 5/5 |
| **eigenanteil-zahl** (enthaelt) | 0/5 | 5/5 | 5/5 |
| **foerderbedingungen-luecke** (llm) | 0/5 | 1/5 | 1/5 |
| **foerderfrist** (llm) | 0/5 | 0/5 | 5/5 |
| **folgekosten-luecke** (enthaelt) | 0/5 | 0/5 | 3/5 |
| **fristen-winterperiode** (enthaelt) | 0/5 | 2/5 | 5/5 |
| **haushaltsjahr-2027** (enthaelt) | 0/5 | 5/5 | 5/5 |
| **kein-erfundener-link** (enthaelt-nicht) | 5/5 | 5/5 | 5/5 |
| **stellplatzbilanz-luecke** (llm) | 0/5 | 0/5 | 0/5 |
| **vorlage-gelesen** (tool-call) | 5/5 | 5/5 | 5/5 |
| **zahlen-aus-vorlage** (zahlen) | 5/5 | 5/5 | 5/5 |
| **zeitplan-luecke** (enthaelt) | 0/5 | 1/5 | 4/5 |

- **ohne Skill** — Median-Wandzeit: 300 s · Median Prompt-Tokens: 38863 · Median Completion-Tokens: 3810 · Läufe mit Timeout/Fehler: 4/5 · ungültige Tool-Calls: 0
  Fehlkriterien: barrierefreiheit-offen fehlt 5/5 · beleuchtung-offen fehlt 5/5 · eigenanteil-zahl fehlt 5/5 · foerderbedingungen-luecke fehlt 5/5 · foerderfrist fehlt 5/5 · folgekosten-luecke fehlt 5/5 · fristen-winterperiode fehlt 5/5 · haushaltsjahr-2027 fehlt 5/5 · stellplatzbilanz-luecke fehlt 5/5 · zeitplan-luecke fehlt 5/5
- **vorige Fassung** — Median-Wandzeit: 71,2 s · Median Prompt-Tokens: 24564 · Median Completion-Tokens: 2136 · Läufe mit Timeout/Fehler: 0/5 · ungültige Tool-Calls: 0
  Fehlkriterien: foerderbedingungen-luecke fehlt 4/5 · foerderfrist fehlt 5/5 · folgekosten-luecke fehlt 5/5 · fristen-winterperiode fehlt 3/5 · stellplatzbilanz-luecke fehlt 5/5 · zeitplan-luecke fehlt 4/5
- **aktuelle Fassung** — Median-Wandzeit: 66,9 s · Median Prompt-Tokens: 9015 · Median Completion-Tokens: 2427 · Läufe mit Timeout/Fehler: 0/5 · ungültige Tool-Calls: 0
  Fehlkriterien: foerderbedingungen-luecke fehlt 4/5 · folgekosten-luecke fehlt 2/5 · stellplatzbilanz-luecke fehlt 5/5 · zeitplan-luecke fehlt 1/5

Kriterien des Falls:
- **barrierefreiheit-offen** (enthaelt, `evals/cases/sitzungsmappe-top3/bewerter/barrierefreiheit-offen.md`): Barrierefreiheit an der Einmündung Gartenweg ist das zweite offene Anliegen
der Vorlage und muss im Abschnitt stehen.
- **beleuchtung-offen** (enthaelt, `evals/cases/sitzungsmappe-top3/bewerter/beleuchtung-offen.md`): Die Beleuchtungskosten sind in den 240 000 € nicht enthalten bzw. unklar —
die Vorlage lässt das Anliegen ausdrücklich offen. Der Abschnitt muss
Beleuchtung als offenen Punkt benennen.
- **eigenanteil-zahl** (enthaelt, `evals/cases/sitzungsmappe-top3/bewerter/eigenanteil-zahl.md`): Der Eigenanteil von 80 000 € belastet den städtischen Haushalt — die Zahl
muss fallen. Das Wort »Eigenanteil« allein genügt nicht (Lehre aus #158:
das lasche K6 zählte Nennungen ohne Betrag und machte aus 2/5 ein 5/5).
- **foerderbedingungen-luecke** (llm, `evals/cases/sitzungsmappe-top3/bewerter/foerderbedingungen-luecke.md`): PASS wenn die Antwort die Förderbedingungen der Landesförderung als Lücke benennt — also sinngemäß sagt, dass die Vorlage Förderquote, Zweckbindung oder Rückforderungsrisiko nicht angibt (eine dieser Bedingungen genügt).
FAIL wenn die Antwort keine Aussage zu den Förderbedingungen trifft (auch wenn sie die Förderung als solche erwähnt).
- **foerderfrist** (llm, `evals/cases/sitzungsmappe-top3/bewerter/foerderfrist.md`): PASS wenn die Antwort einen terminlichen Bezug der Förderung nennt — z. B. den Zuwendungsbescheid vom 19.09.2026, einen Bewilligungs- oder Abrufzeitraum, eine Frist für den Mittelabruf — ODER ausdrücklich als Lücke benennt, dass die Vorlage keine Förderfrist (Mittelabruf, Bewilligungszeitraum) angibt.
FAIL wenn die Antwort zur Förderung keinen terminlichen Bezug herstellt und die fehlende Förderfrist auch nicht als Lücke benennt.
Hintergrund: Das Regex-Kriterium aus #158 (»Frist für den Abruf der Landesförderung«) war zu eng und warf Nennungen mit anderer Wortstellung weg; deshalb hier der Richter mit konkreter PASS-Bedingung statt eines strengeren Regex.
- **folgekosten-luecke** (enthaelt, `evals/cases/sitzungsmappe-top3/bewerter/folgekosten-luecke.md`): »Was die Vorlage nicht sagt«: Die Vorlage nennt nur Baukosten; laufende
Kosten (Pflege, Unterhalt, Betrieb) fehlen und müssen als Lücke benannt
werden. Die Fixture erwähnt keines dieser Wörter — jeder Treffer in der
Antwort ist eine benannte Lücke, kein Abschreibfehler.
- **fristen-winterperiode** (enthaelt, `evals/cases/sitzungsmappe-top3/bewerter/fristen-winterperiode.md`): Fristen, die das Vorhaben binden, müssen mit Datum/Bedingung benannt
werden; die Pflanzung erst nach der Winterperiode ist die ausdrückliche
Auflage der Vorlage.
- **haushaltsjahr-2027** (enthaelt, `evals/cases/sitzungsmappe-top3/bewerter/haushaltsjahr-2027.md`): Der Beschlussvorschlag meldet die Kostenschätzung zur Haushaltsplanung
2027 — das Haushaltsjahr ist die Frist, an der die Finanzierung hängt.
In dieser Fixture kommt 2027 ausschließlich in diesem Bezug vor.
- **kein-erfundener-link** (enthaelt-nicht, `evals/cases/sitzungsmappe-top3/bewerter/kein-erfundener-link.md`): Kriterium aus #292: keine URL und kein Abrufdatum, die nicht aus einem
Werkzeug-Ergebnis stammen. Die Fixture enthält weder Link noch Abrufdatum
und der Lauf hat nur das read-Tool — jede URL und jedes Abrufdatum in der
Antwort kommt aus dem Training, nicht aus einer Quelle. Im Vorlauf #158
erfand das Modell ris.komuna.net/…?meeting=2026-11-12 mit »abgerufen am
21.10.2026« in 2/5 Läufen.
- **stellplatzbilanz-luecke** (llm, `evals/cases/sitzungsmappe-top3/bewerter/stellplatzbilanz-luecke.md`): PASS wenn die Antwort die Stellplatzbilanz als Lücke benennt: dass die Vorlage nicht sagt, wie viele Parkbuchten heute entfallen bzw. wie sich die Zahl der Stellplätze vor und nach der Umgestaltung verhält (die 14 Stellplätze in Randzonen sind die Zahl danach, nicht die Bilanz).
FAIL wenn die Antwort die Stellplatzsituation nicht als Lücke benennt — auch wenn sie die 14 Stellplätze oder die Parkbuchten sonst erwähnt.
- **vorlage-gelesen** (tool-call, `evals/cases/sitzungsmappe-top3/bewerter/vorlage-gelesen.md`): Der Abschnitt muss aus der gelesenen Vorlage stammen, nicht aus dem
Prompt-Rest. Ein Lauf, der die Vorlage nie öffnet, beantwortet den Fall
nicht, er rät.
- **zahlen-aus-vorlage** (zahlen, `evals/cases/sitzungsmappe-top3/bewerter/zahlen-aus-vorlage.md`): Zahlen nur aus der Vorlage (Skill-Checkliste, AGENTS.md §6): keine erfundenen
Zahlen; selbst gebildete (z. B. Förderanteil 160 000 = 240 000 − 80 000) sind
erlaubt, müssen aber als abgeleitet gekennzeichnet sein. Erfundene und
abgeleitete Zahlen werden je Lauf protokolliert.
- **zeitplan-luecke** (enthaelt, `evals/cases/sitzungsmappe-top3/bewerter/zeitplan-luecke.md`): Die Vorlage enthält keinen Zeitplan (kein Baubeginn, keine Bauzeit), obwohl
Förderung und Haushaltsjahr daran hängen — das ist eine Lücke und muss als
solche benannt werden. Die Fixture keines dieser Wörter; das Lieferzeitfenster
(»Zeitfenster von 6 bis 9 Uhr«) ist kein Zeitplan und wird vom Regex nicht
getroffen.

## Fall: trigger-sitzungsmappe (trigger)

Trigger-Fall: Die Description des Skills muss greifen. pi läuft mit dem echten Skill-Mechanismus (alle Skills registriert, keiner an den System-Prompt angehängt); gemessen wird, ob das Modell die SKILL.md des Zielskills per read lädt — und ob die geladene Anweisung die Antwort prägt.

> Prompt: „Ich brauche die Sitzungsmappe für die Sitzung am 12.11.2026. Die Vorlage für TOP 3 liegt als top-3-anhoerung.md im aktuellen Verzeichnis.“
> Quelle des Falls: Issue #292: »mindestens ein Trigger-Fall je Skill (die description muss greifen)«
> Fixtures (synthetisch): `fixtures/top-3-anhoerung.md`
> Arm: echte Skill-Auswahl über pis `--skill`-Mechanismus — alle 11 Skills registriert, kein Anhängen an den System-Prompt. Gemessen wird, ob der Skill per `read` geladen wird (Trigger) bzw. nicht geladen wird (Negativ).

| Kriterium (Bewerter) | aktuelle Fassung |
|---|---|
| **eigenanteil-zahl** (enthaelt) | 0/5 |
| **kein-erfundener-link** (enthaelt-nicht) | 5/5 |
| **skill-gelesen** (tool-call) | 4/5 |
| **vorlage-gelesen** (tool-call) | 5/5 |

- **aktuelle Fassung** — Median-Wandzeit: 240 s · Median Prompt-Tokens: 200013 · Median Completion-Tokens: 5372 · Läufe mit Timeout/Fehler: 4/5 · ungültige Tool-Calls: 0
  Fehlkriterien: eigenanteil-zahl fehlt 5/5 · skill-gelesen fehlt 1/5
  Gelesene Skills je Lauf: sitzungsvorbereitung 4/5

Auffälligkeiten (automatisch gesammelt):
- Ziel-Skill gelesen: 4/5 Läufe

Kriterien des Falls:
- **eigenanteil-zahl** (enthaelt, `evals/cases/trigger-sitzungsmappe/bewerter/eigenanteil-zahl.md`): Folgekriterium des Trigger-Falls: Zeigt, ob der geladene Skill die Antwort
tatsächlich prägt — der Eigenanteil (Zahl, nicht nur Wort) gehört in jeden
Finanzierungs-TOP der Mappe.
- **kein-erfundener-link** (enthaelt-nicht, `evals/cases/trigger-sitzungsmappe/bewerter/kein-erfundener-link.md`): Folgekriterium des Trigger-Falls: Die Fixture enthält weder Link noch
Abrufdatum; jede URL und jedes Abrufdatum in der Antwort ist erfunden
(Vorlauf #158: 2/5 Läufe mit erfundener RIS-URL nebst Abrufdatum).
- **skill-gelesen** (tool-call, `evals/cases/trigger-sitzungsmappe/bewerter/skill-gelesen.md`): Das Kernkriterium des Trigger-Falls: pi annonciert alle Skills im
System-Prompt (<available_skills> mit Name, Description, Pfad) und das
Modell muss die SKILL.md des passenden Skills selbst per read laden.
Kommt dieser Aufruf nicht, greift die Description nicht.
- **vorlage-gelesen** (tool-call, `evals/cases/trigger-sitzungsmappe/bewerter/vorlage-gelesen.md`): Der Abschnitt muss aus der gelesenen Vorlage stammen.

## Stichproben-Notizen

Stichproben aus den Messläufen (je Fall und Arm Antworten gelesen; Zitate
wortgetreu). Werksnotizen, keine Zählung — die Zahlen stehen in den Tabellen
oben.

**Zur Richter-Phase:** Der erste Richter-Durchlauf wertete 59 von 60
llm-Kriterien als „unbestimmt" und damit FAIL — Gemma 4 26B-A4B-it denkt vor
der Antwort in `reasoning_content` (englisch), und das ursprüngliche
Output-Budget von 256 Token schnitt jeden Lauf mitten im Denken ab
(`finish_reason: length`, leerer `content`). Das war ein Fehler im
LLM-as-a-Judge (judge bug), kein Befund über die Antworten: Die Messläufe
selbst blieben unberührt; die
Richter-Phase wurde nach dem Fix (2 048 Token Budget, Urteil auch aus dem
Ende der Denkspur lesbar) über dieselben gespeicherten Antworten wiederholt.
Die llm-Zahlen in den Tabellen stammen aus dem zweiten Durchlauf. Lehre für
die Konvention: Richter-Smokes müssen mit Antwortlängen aus der echten
Messung laufen, nicht mit Kurzfassungen — der Smoke mit Ein-Satz-Antworten
sah grün aus.

**Kernfall sitzungsmappe-top3**

- **ohne Skill:** 4 von 5 Läufen enden im Timeout — das Modell läuft in
  read-Schleifen über die Vorlage (bis 24 Requests, 104 551 Prompt-Tokens in
  einem Lauf) und produziert nie eine Mappe. Der eine abgeschlossene Lauf
  liest die Vorlage — die exakt die drei genannten Inhalte bereithält — und
  fragt trotzdem: „Gibt es eine Datei im Verzeichnis, aus der ich diese
  Informationen entnehmen soll, oder möchtest du sie mir direkt hier geben?“
  Ohne Skill entsteht in keinem Lauf eine Mappe; der Fall wird nicht
  unvollständig, sondern gar nicht erledigt.
- **vorige Fassung (834 Zeilen):** Der Eigenanteil von 80 000 € taucht nur in
  einem RIS-Kontextabsatz auf, nicht im Finanzierungsfeld; ein Block „Was die
  Vorlage nicht sagt“ fehlt in den meisten Läufen. Die Checkliste der langen
  Fassung trägt nicht in die Antwort — das Bild aus #158 („im langen Skill
  geht die Checkliste unter“) wiederholt sich messbar.
- **aktuelle Fassung (kompakt):** Vollständige Checklisten-Antworten —
  Finanzierungsfeld mit 80 000 € Eigenanteil und 160 000 € Förderanteil
  ausdrücklich als „(abgeleitet)“ gekennzeichnet, Fristenblock (Winterperiode,
  Zeitfenster, Haushaltsjahr 2027), Lücken-Block mit je Grund benannten Lücken
  und Fraktionsfragen. Ein Lauf verlor nur die Folgekosten-Lücke.

**Kurzprompt-top3**

- **ohne Skill:** Gremium, Datum, Gesamtkosten und Beschlusskomponenten
  kommen — der Eigenanteil fehlt in jedem der 5 Läufe. Exakt der Befund aus
  #158, jetzt als committete Regressionsserie mit strengem K6 (Zahl statt
  Wort).
- **vorige Fassung:** dasselbe K6-Bild (4/5 Läufe ohne die Zahl) bei rund
  24 000 Prompt-Tokens je Lauf — die lange Fassung kostet den dreifachen
  Kontext und liefert die Finanzierungsstruktur trotzdem nicht verlässlich.
- **aktuelle Fassung:** nennt die Zahl; ein Lauf verliert sie (4/5).

**formaler-top (Negativverhalten)**

- **ohne Skill:** instabil — einmal Rückfragen („benötige ich noch ein paar
  Informationen … (statt 12.11.2026)“, es hält sogar die Vorlagen-Daten für
  klärungsbedürftig), zweimal Timeout in read-Schleifen (bis 118 072
  Prompt-Tokens), einmal eine Zeile.
- **vorige Fassung:** bläht die Protokollgenehmigung zum Vollformat auf —
  Status-Zeile, Dokumente-Zeile, Kontextblöcke (RIS, AZ, Vault, Ratsprojekt)
  und „Fragen für die Fraktion: Gibt es Einwände oder Korrekturbedarf zum
  Protokoll …?“. Die mechanische Überanwendung, gegen die der Fall schützt.
- **aktuelle Fassung:** erkennt und schreibt: „Da es sich bei TOP 1 um eine
  formale TOP (Protokollgenehmigung) handelt, wird sie gemäß den Richtlinien
  der Sitzungsvorbereitung in einer einzigen Zeile aufbereitet“ — dann die
  eine Zeile.

**trigger-sitzungsmappe (echter Skill-Mechanismus)**

- Die Description greift: In 4 von 5 Läufen lädt das Modell die SKILL.md von
  sitzungsvorbereitung per read — richtig gewählt aus 11 registrierten
  Skills. Danach folgt es dem Ablauf und verheddert sich an Schritt 1: Es
  sucht `config.local.yml` für den Vault-Namen, probiert 20 weitere Pfade
  (`../config.local.yml`, `../../config.local.yml`, `.` …), fragt nie nach
  und läuft in 4 von 5 Läufen in den Timeout (bis 341 151 Prompt-Tokens). Der
  eine abgeschlossene Lauf endet in einer Config-Diskussion statt in einer
  Mappe. Der Skill schreibt vor: „Fehlt er: nachfragen“ — die
  Rückfrage-Anweisung trägt bei Gemma nicht, wenn sie mitten im Ablauf
  steht. Produktiv existiert die Datei, aber jede andere fehlende
  Voraussetzung könnte dasselbe stille Suchen auslösen. Offene Baustelle für
  die nächste Skill-Fassung: fehlende Voraussetzungen auffälliger machen
  (eigener Absatz statt Halbsatz) und im Trigger-Fall der Suite eine
  synthetische `config.local.yml` als Fixture mitgeben, damit der Ablauf
  weiterläuft.

**negativ-antrag**

- Der Antrag wird in jedem Lauf entworfen (bis auf Details wie
  Fraktionsnamen vollständig), die SKILL.md von sitzungsvorbereitung wird in
  keinem Lauf geladen — die Description grenzt sauber ab. Bemerkenswert: In
  dieser Messrunde las das Modell in den Negativ-Läufen überhaupt keine
  Skill-Datei, auch nicht die von antrag_generieren — es schreibt den
  Antrag direkt aus dem Kontextwissen. Ein separates Vorlauf-Experiment
  (Smoke, gleicher Prompt) las dagegen die SKILL.md von vault_suche — die
  Skill-Wahl streut bei diesem Prompt; gemessen und gezählt bleibt hier nur
  die Nicht-Wahl des Ziel-Skills.

## Nicht gemessen

- Läufe hatten nur die in den Fällen konfigurierten Tools — Schreib- und Netzschritte (z. B. „Quellen verifizieren“ mit Abruf) sind nicht Teil dieser Messung

## Reproduktion

```bash
komki up
node apps/komki_cli/experiments/pi_packages/skill-evals/run.mjs --skill sitzungsvorbereitung --baseline 9c50fa1
```
