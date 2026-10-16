# Recherche: Datalog-Engine-Optionen für Elixir

> Librarian-Report (lib-2), abgeschlossen am 2026-09-03. Auftragsgrundlage: RFC 0002, offene Frage OF-1. Unverändert übernommen; die gekennzeichneten Lücken L1 bis L5 sind Teil des Befunds.

## Datalog-Engine-Optionen — Entscheidungstabelle (RFC-0002 / Abschnitt OF-1)

Recherche abgeschlossen (kompakt, mit bewusst gekennzeichneten Lücken). Kurzfazit: Für den bounded Pilotfall (positive Horn-Klauseln, ohne Negation, Bereichsprüfungen, Atome, strukturierte Objekte) gibt es **keinen fertigen, gepflegten Elixir/Erlang-** und **keinen pflegeleichten kleinen Rust-** Kandidaten. Soufflé ist die einzige produktionsreife Engine, bringt aber ein Fremd-Binary, kein natives JSON und eine ARM-Caveat mit. Der **eigene semi-naive Interpreter in Elixir ist für genau diesen Fall der niedrigste-Aufwand-Weg** und liegt im Bereich weniger Tage.

### Entscheidungstabelle

| Option | Sprache | Integration → Elixir | Pflegezustand | Lizenz | Eignung (1 Satz) |
|---|---|---|---|---|---|
| **Soufflé** | C++ (Native) | **CLI/Port** (Subprozess, `System.cmd`) | Stabil; letztes Stable-Release **2.5 (03/2025**, ~1,5 J. alt); dokumentiertes **ARM-Concurrency-Issue #2476** | **UPL** (Universal Permissive License, permissiv, Apache-2.0-kompatibel) | **Mittel** – robuste Datalog-Engine mit Interpreter-Modus, aber **kein natives JSON** (nur CSV/TSV/rfc4180/SQLite/Terminal), extra Binary + Build/Homebrew auf macOS, ARM-Caveat relevant fürs Apple-Silicon-Homelab. |
| **`datalog`-Crate** (≈ „datalog-rs") | Rust | **NIF** (Rustler) | **Abandoniert** – selbst „INCOMPLETE!", Stand **0.0.2 (2017)** | MIT | **Niedrig** – als NIF-Basis ungeeignet, man müsste selbst forken & pflegen. |
| **`nemo`** | Rust | **NIF** (Rustler) | **Aktiv** (Push 09/2026), produktionsorientiert | Apache-2.0 | **Mittel** – fertig, aber **RDF/Rule-Engine-Schwerpunkt** → mehr Glue-Code für den simplen Horn-Fall; NIF realistisch, aber aufwändiger als Eigenbau/CLI. |
| **`datafrog`** | Rust | **NIF** (Rustler) | **Aktiv** (Push 08/2026), rust-lang-Org; Research-Charakter | Apache-2.0 | **Mittel** – „lightweight Datalog engine", aber low-level-API auf differential-dataflow; kein fertiges „Horn + strukturiertes Output". |
| **`egglog` / `cozo` / `crepe`** | Rust | **NIF** (Rustler) | egglog aktiv; cozo stagniert (12/2024); crepe moderat (12/2025) | egglog MIT / cozo MPL-2.0 / crepe Apache-2.0 | **Niedrig** für diesen Fall – andere Zielsetzung (e-graphs / Volldatenbank / Proc-Macro-Compiler), Überkill. |
| **Pure Elixir/BMAM** | Elixir/Erlang | **pure** | **Nichts Gepflegtes** – einzige Datalog-`hex`-Paket `datalog` seit **02/2019 dorm** (~1,4k Downloads, keine Doku); kein `mini_kanren`/`kanren`; GitHub zeigt **keine** Elixir/Erlang-Datalog- oder miniKanren-Repos (nur Scheme/Racket/Haskell) | (hex `datalog`: Apache) | **Niedrig** – kein wartbares off-the-shelf reines Elixir-Äquivalent. |
| **Eigenbau: mini Datalog-Interpreter** | Elixir | **pure** | selbst verantwortbar | dein Repo | **Hoch** (für den bounded Fall) – positives Datalog ohne Negation ist **monoton → semi-naiver Fixpunkt ohne Stratifikation**, DSL kompiliert bereits zu Fakten/Regeln, realistisch **~200–400 LOC**, Aufwand = wenige fokussierte Tage für eine BEAM-erfahrene Person; schwerster Teil = Multi-Atom-Body-Joins + Unification. |

### Details zu den einzelnen Prüfpunkten

**1. Soufflé** – Lizenz **UPL** (permissiv). **CLI-JSON-Output: nein.** Aktuelle Direktive unterstützt nur `IO=[file|stdout|sqlite]` mit `delimiter`/`compress`/`rfc4180`; Records/ADTs werden als String serialisiert, aber es gibt kein JSON-Format → in Elixir CSV→JSON parsen. Release-Stand **2.5 (24.03.2025)**; die einzigen offiziellen Binaries sind Linux (deb/rpm), macOS erfordert Build/Homebrew. **Betrieb ohne IT-Team:** CLI-Modus = lockere Kopplung (einfachster Betrieb), aber die **bekannte ARM-Concurrency-Problematik (#2476)** spricht bei Apple Silicon dagegen; Interpreter-Modus reicht für kleine Programme.

**2. Rust-Crates** – `datalog`-Crate ist **toter** (2017, „INCOMPLETE!"). Aktiv gepflegte Alternativen: **`nemo`** (Apache-2.0, RDF-orientiert) und **`datafrog`** (Apache-2.0, rust-lang, lightweight/Research). **NIF-Realismus für eine Person:** Rustler ist ein etabliertes, reifes Elixir-NIF-Framework → technisch machbar. Aber: (a) zweite Sprach-Toolchain in Dev + CI, (b) nativer Build-Schritt, (c) Du erbst die Upstream-Pflege & API-Breakage der Crate, (d) bei `nemo`/`datafrog` großem/low-level API-Surface → **deutlich mehr Glue-Code als bei CLI oder Eigenbau**. Fallback auf die tote `datalog`-Crate = selbst pflegen = zu riskant.

**3. Pure Elixir/Erlang** – **Klar: es existiert nichts Gepflegtes.** Einzige Datalog-`hex`-Paket `datalog` (Apache) ist seit 2019 dorm; kein miniKanren/kanren; GitHub-Repos zu Datalog/miniKanren existieren nur in Scheme/Racket/Haskell. *(Siehe Lücke L1.)*

**4. Eigenbau-Aufwand (semi-naive, ohne Negation, ohne tiefe Rekursion)** – **gering bis moderat.** Begründung aus Standardliteratur: Die **semi-naive Bewertung** ist der kanonische Algorithmus für Datalog (Abiteboul/Hull/Vianu, *Foundations of Databases*, Addison-Wesley, 1995, **Kap. 9 „Datalog", §9.3.2 „Semi-naive Evaluation"**; frei verfügbar: [Datalog – Wikipedia](https://en.wikipedia.org/wiki/Datalog)). Weil die Klauseln **positiv** (ohne Negation) sind, ist das System **monoton**: kein Stratifikationsproblem, Terminierung durch Monotonie, worst-case Iterationen = Rekursionstiefe (hier beschränkt). Da die DSL bereits zu Fakten/Regeln kompiliert, bleibt nur der Fixpunkt über Join/Unification + eine Built-in für den Zahlenbereich (9001…25000) + Mapping der finalen Relation auf Elixir-Strukturen. Realistisch **~200–400 LOC**, d. h. **einige Tage** für jemanden mit BEAM-Erfahrung; der größte Teil entfällt auf korrekte Multi-Atom-Body-Joins.

**5. LegalRuleML / Akoma-Ntoso (Kurzeinschätzung)** – **LegalRuleML:** OASIS-Spezifikation (RDF/OWL + Rule Language), Referenz-Repos sind dorm (zuletzt 2018/2020) → Tooling ist vor allem Beispielsammlung, **kein gepflegter Referenz-Interpreter**. **Akoma-Ntoso:** etabliertes, stabiles OASIS-XML-**Dokumentenformat** (kein Engine), Schema-Repo ruhig (zuletzt 2022), aktivste Ökosystem-Nutzung über **Indigo** (Python, Legislation-Publishing). *(Siehe Lücke L4.)*

### Quellen
- Soufflé: [UPL-Lizenz](https://github.com/souffle-lang/souffle/blob/master/licenses/SOUFFLE-UPL.txt) · [Output-Direktiven (kein JSON)](https://souffle-lang.github.io/directives.html) · [Release 2.5 (03/2025)](https://github.com/souffle-lang/souffle/releases/tag/2.5) · [ARM-Issue #2476](https://github.com/souffle-lang/souffle/issues/2476)
- Rust: [`datalog` (abandoniert)](https://crates.io/crates/datalog) · [`nemo`](https://github.com/knowsys/nemo) · [`datafrog`](https://github.com/rust-lang/datafrog) · [`egglog`](https://github.com/egraphs-good/egglog) · [`cozo`](https://github.com/cozodb/cozo) · [`crepe`](https://github.com/ekzhang/crepe) · [Rustler-Doku](https://hexdocs.pm/rustler/)
- Elixir/BEAM: [hex `datalog` (dorm, 2019)](https://hex.pm/packages/datalog) · [miniKanren (nur Scheme/Racket/Haskell)](https://github.com/miniKanren/miniKanren)
- Eigenbau-Referenz: [Datalog – Wikipedia](https://en.wikipedia.org/wiki/Datalog) + Abiteboul/Hull/Vianu, *Foundations of Databases* (1995), Kap. 9, §9.3.2
- LegalRuleML/Akoma-Ntoso: [oasis-tcs/legalruleml](https://github.com/oasis-tcs/legalruleml) · [oasis-open/legaldocml-akomantoso](https://github.com/oasis-open/legaldocml-akomantoso) · [laws-africa/indigo](https://github.com/laws-africa/indigo)

### Kennzeichnete Lücken (nicht weiter recherchiert)
- **L1 (Punkt 3, wichtigste Unsicherheit):** Die Hex-Such-API lieferte 404; ich habe gezielt die plausiblen Paketnamen `datalog` / `mini_kanren` / `kanren` geprüft und GitHub-Repos durchsucht. Eine gepflegte Logik-Bibliothek **unter einem anderen Namen** ist theoretisch möglich, aber unwahrscheinlich → „nichts Gepflegtes" steht unter diesem Vorbehalt.
- **L2 (Punkt 2):** Der NIF-Realismus ist eine **Schätzung** aus API-Fläche + Rustler-Reife, **kein empirischer Build** (keine Crate tatsächlich als NIF verdrahtet).
- **L3 (Punkt 1):** Soufflé-Installation auf macOS/ARM (v. a. Homebrew-Verfügbarkeit) **nicht verifiziert**; das ARM-Issue #2476 stammt aus den 2.5-Release-Notes und wurde **nicht reproduziert**.
- **L4 (Punkt 5):** Pflegezustand von LegalRuleML/Akoma-Ntoso basiert nur auf **Letztem-Push-Datum der Referenz-Repos**, kein vollständiges Tooling-Audit.
- **L5:** `nemo`/`datafrog` als konkrete Elixir-NIF-Basis **nicht** jenseits von „Rust-Lib vorhanden" geprüft (keine API-Anbindung bewertet).
