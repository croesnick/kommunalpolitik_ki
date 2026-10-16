# RFC 0004: Formalisierung von Rechtsgrundlagen für AI-Agents

| Feld | Wert |
|---|---|
| Status | Draft, in Diskussion |
| Datum | 2026-09-03 |
| Überarbeitet | 2026-09-04 (Befunde der Gegenlesung eingearbeitet) |
| Modus | Nur Planung. Nichts wird gebaut. Jede Umsetzung braucht vor dem Start ein GO (Repo-Prinzip 7) |
| Grundlage | docs/rechtsgrundlagen/exzerpt.md (Exzerpt des Stadtrats, Stand 21.08.2026, Pilotfall Bahnhofstrasse / St 2035) |

> RFC-Konvention: RFCs liegen unter `docs/rfcs/`, Name `NNNN-slug.md`, Status im Kopf. Dies ist der zweite RFC im Repo; die Konvention stammt aus RFC 0001 (Worktree threat-modelling). RFC 0001 liegt dort als uncommitteter Entwurf; bis zu seiner Übernahme ist die Referenz nur über den Worktree auflösbar.
>
> **Bergung 2026-10-16:** Dieser Entwurf entstand 2026-09-03/04 im Worktree `rechtsgrundlagen-formalisierung` — dort als RFC 0002 geführt, nie committet (Vor-Rewrite-Historie) — und wurde inhaltlich unverändert als **RFC 0004** übernommen, weil main inzwischen ein anderes RFC 0002 hat (`0002-system-1-modelle.md`). Der obenstehende Satz zur Worktree-Auflösbarkeit von RFC 0001 ist historisch: RFC 0001 ist inzwischen committet. Triage: [#126](https://github.com/croesnick/kommunalpolitik_ki/issues/126).

## Zusammenfassung

LLMs beantworten Rechtsfragen falsch, wenn die Frage binär gestellt wird. „Darf die Stadt das?" erzeugt Ja oder Nein, wo das Recht Modalitäten kennt: Die Stadt darf beantragen, ohne einen Anspruch auf die gewünschte Entscheidung zu haben; die Befugnisübertragung steht beiden Seiten offen, aber niemandem zu. Recht ist zudem zuständigkeitsgeschichtet (Strassenklasse, Baulast, Verkehrsrecht, Bauleitplanung) und epistemisch abgestuft (beglaubigter Bescheid gegen Planungsentwurf). Dieser RFC definiert eine Repräsentation, die beides abbildet: Objekte, rechtliche Modalitäten und epistemische Status als Datenmodell, vier Schichten als Architektur, strukturierte Begründungsobjekte als Ausgabekontrakt statt Boolescher Werte. Abnahmekriterium der Phase 1 ist der Pilot: Art. 58 Abs. 4 BayStrWG als Datalog-Regel mit sechs testbaren Grenzfällen. Abnahmekriterium der Phase 2 ist zusätzlich die kontraktkonforme Radfahrstreifen-Antwort aus Art. 58 Abs. 4, Art. 44 BayStrWG und § 45 StVO (Abschnitt 8).

## 1. Fragestellung und Prinzipien

Frage: Wie muss eine Repräsentation von Rechtsgrundlagen beschaffen sein, damit ein AI-Agent Fragen nach Zuständigkeit, Hebeln und Verfahrenswegen korrekt, nachvollziehbar und quellenbelegt beantwortet?

Fünf Prinzipien:

- **P1 (Modalität vor Wahrheit).** Keine Aussage ist schlicht wahr oder falsch; jede trägt eine rechtliche Modalität. `true` ist keine zulässige Antwortform.
- **P2 (Epistemische Ehrlichkeit).** Jede Tatsache trägt ihren Quellenstatus. Ein Planungsentwurf ist keine amtliche Tatsache.
- **P3 (Unbestimmte Rechtsbegriffe bleiben offen).** „Erheblich breiter", „angemessen", „überwiegende Gründe des öffentlichen Wohls" sind Prüfobjekte mit Beweisanforderungen, keine Booleschen Variablen. Die rechtlich zuständige Stelle bleibt als Entscheider sichtbar.
- **P4 (Beraten, nicht entscheiden).** Ausgaben sind Arbeitsgrundlagen für Stadtrat und Verwaltung. Die Entscheidung bleibt bei Mensch und Behörde (Repo-Prinzip 7).
- **P5 (Quellenpflicht).** Jede Normreferenz ist absatzgenau und versioniert, jede Tatsache hat eine Quelle mit Abrufdatum (Repo-Prinzip 6). Das heutige Exzerpt erfüllt beides noch nicht; die Lücke steht in Abschnitt 12 und wird bei der Übernahme in Schicht 1 geschlossen.

## 2. Anforderungen aus dem Pilotfall

Die Fachlichkeit steht im Exzerpt: vier Kompetenzschichten, sechs Hebel, eine Vorhabens-Tabelle, ein Beschlussentwurf. Jedes Fachphänomen erzwingt eine Repräsentationsentscheidung:

| Fachphänomen im Exzerpt | Erforderliche Repräsentation |
|---|---|
| „Staatsstrasse" beantwortet nicht, wer was entscheiden darf | Kompetenzschichten als getrennte Objekte: Authority je Gegenstand (Klasse, Baulast, Verkehrsrecht, Planung) |
| Befugnisübertragung nur per Vereinbarung, kein einseitiger Anspruch | Modalität may_agree mit decision_mode negotiated_discretion, kein has_claim |
| Zensus wird erst zum 1.1.2025 maßgeblich | TemporalValidity an Fakten (binding_census.valid_from) |
| FNP-Entwurf gegen beglaubigten Straßenverzeichnisauszug | epistemic_status asserted gegen verified, mit verification_required |
| Vorhabens-Tabelle „Kann Buchloe allein entscheiden?" | cannot_unilaterally und required_decisions im Antwortobjekt |
| StVO-Antrag statt Anspruch auf Genehmigung | Modalität may_apply ohne has_claim |
| „Erheblich breiter", „angemessene Flächen" | Prüfobjekte (assessment), nie binarisiert |
| Ortsdurchfahrtsgrenzen, seitliche Begrenzung | SpatialScope; MVP führt Geometrie mit epistemic_status unknown |
| Förderfrist 31.12.2026 (nur Barrierefreiheit und Bahnstationen) | TemporalValidity an Normen und Fristen |

## 3. Objekte

| Objekt | Bedeutung |
|---|---|
| Fact | Tatsache im Fall, mit epistemischem Status und Quelle |
| Norm | Rechtsnorm mit absatzgenauer ID und Version |
| Actor | Person, Gemeinde, Behörde |
| Authority | Entscheidungsbefugnis eines Actors für einen Gegenstand |
| LegalRole | Rolle eines Actors in einem Verfahren (Baulastträger, Antragsteller, Behörde) |
| Action | Handlung (anordnen, beantragen, vereinbaren, übertragen) |
| Condition | Tatbestandsvoraussetzung |
| Exception | Ausnahme von einer Regel |
| Procedure | Verfahren mit Schrittfolge und Beteiligten |
| Consent | Zustimmung eines Actors zu einer Handlung |
| Agreement | Vereinbarung zwischen Actors (etwa nach Art. 58 Abs. 4) |
| Evidence | Beweisstück mit Beweisziel |
| LegalEffect | Rechtsfolge |
| Discretion | Ermessen, wo keine feste Rechtsfolge existiert |
| Source | Quelle mit URL, Abrufdatum, Version |
| SpatialScope | räumliche Geltung (Strassenabschnitt, Gemarkung, Flächenanteil) |
| TemporalValidity | zeitliche Geltung (valid_from, valid_to) |

## 4. Modalitäten

| Modalität | Bedeutung |
|---|---|
| may_decide | Behörde besitzt Entscheidungskompetenz |
| must_decide | Behörde muss nach Antrag entscheiden |
| may_apply | Akteur darf ein Verfahren anstossen |
| may_agree | Akteure dürfen eine Vereinbarung schliessen |
| requires_consent | Handlung benötigt Zustimmung eines anderen |
| must_agree | Einvernehmen ist gesetzlich erforderlich |
| must_hear | Beteiligter ist anzuhören |
| may_plan | Planungskompetenz |
| must_reclassify | Rechtsfolge bei festgestelltem Tatbestand |
| has_claim | Betroffener kann ein bestimmtes Ergebnis verlangen |

Der fehlerverhütende Kern ist die Differenz zwischen `may_agree` und `has_claim`:

```text
Art. 58 Abs. 4 BayStrWG:
    city has an agreement option
    city does not have unilateral transfer power

§ 45 Abs. 1j StVO:
    city has an application right
    city does not automatically have a right to approval

Art. 42 Abs. 3 BayStrWG:
    city and road authority must negotiate the lateral boundary
    government decides if no agreement is reached
```

Diese Differenz verhindert typische Agentenfehler. Die Modalitäten machen den Unterschied strukturell sichtbar statt prompt-abhängig.

## 5. Epistemische Status

| Status | Bedeutung | Beispiel aus dem Pilotfall |
|---|---|---|
| verified | amtlich verifiziert | beglaubigter Straßenverzeichnisauszug (noch anzufordern) |
| asserted | aus plausibler Quelle behauptet | FNP-Entwurf nennt die Bahnhofstrasse als Ortsdurchfahrt |
| inferred | aus Regeln abgeleitet | Art.-58-Abs.-4-Eignung aus Zensus, Strassenklasse und (asserted) Ortsdurchfahrt |
| disputed | umstritten | keine Verwendung im Pilot |
| superseded | von neuerer Quelle ersetzt | früherer Zensus, ab 1.1.2025 vom Zensus 2022 abgelöst |
| unknown | offen | bestehende Vereinbarungen nach Art. 58 Abs. 4 oder Art. 44 |

Der Status ist Teil der Identität einer Tatsache, keine nachträgliche Annotation. Das Casefile im Exzerpt trägt ihn noch uneinheitlich: road_class und ortsdurchfahrt führen epistemic_status, binding_census nur source_status: official, geometry nur status: unknown. Das Objektmodell normiert alle drei Marker auf ein Feld epistemic_status je Fact; diese Normierung ist Teil der Pilotarbeit, nicht bereits geleistet. Ableitungen übernehmen im MVP den schwächsten Status ihrer Prämissen (OF-7): Die Art.-58-Abs.-4-Eignung ruht auf ortsdurchfahrt asserted (FNP-Entwurf) und kann nicht mehr sein als ihre schwächste Prämisse. Ebenfalls offen: Das Casefile bindet Quellen nur über source_type- und source_status-Marker, und die 18 Fussnoten des Exzerpts tragen keine Abrufdaten. Die Quellenbindung mit Abrufdatum (P5) wird bei der Übernahme in Schicht 1 nachgetragen; sie ist Zielzustand des Systems, nicht Beschreibung der heutigen Grundlage.

## 6. Architektur: vier Schichten

| Schicht | Zweck | MVP-Ausprägung | Ausbaustufe |
|---|---|---|---|
| 1 Normquellen | versionierte Gesetzestexte und Bescheide, absatzgenaue IDs | Dateien im Repo, manuell gepflegt (Markdown mit Frontmatter) | Akoma Ntoso |
| 2 Fakten und Geodaten | Falldaten mit epistemischem Status | YAML-Casefiles (Beispiel im Exzerpt, nach Normierung der Status- und Quellenmarker) | PostgreSQL/PostGIS, RDF/JSON-LD, GeoSPARQL |
| 3 Regeln | ausführbarer Kern | Datalog-Fakten und -Regeln, kompiliert aus einer Elixir-DSL | LegalRuleML-äquivalente Ausdruckskraft |
| 4 Begründungsobjekte | Ausgabekontrakt je Anfrage | JSON-Objekte mit Pflichtfeldern und Quellen | PROV-O-Provenienz |

Bewusste Verzichte im MVP (Repo-Prinzip 3): keine LegalRuleML-Vollimplementierung, keine Datenbank, keine Normen-Scraping-Pipeline. Der Pilot läuft mit einer Normgruppe, einem Casefile und einer Regeldefinitionsdatei. Die Standards (Akoma Ntoso, LegalRuleML, PROV-O, GeoSPARQL) sind Richtungsmarken für die Ausbaustufen, keine Bausteine des MVP.

## 7. Ausgabekontrakt: Begründungsobjekte

Kanonische Frage: „Darf Buchloe auf der Bahnhofstraße einen Radfahrstreifen anordnen und bauen?" (wörtlich aus dem Exzerpt)

Die Antwort ist nicht `true` oder `false`, sondern:

```json
{
  "result": "conditionally_feasible",
  "action": "create_cycle_lane",
  "road": "road:st2035:buchloe:bahnhofstrasse",
  "city_roles": [
    "applicant",
    "urban_planner",
    "possible_project_sponsor"
  ],
  "city_cannot_unilaterally": [
    "issue_final_stvo_order",
    "rebuild_state_carriageway"
  ],
  "required_decisions": [
    {
      "actor": "authority:landratsamt_ostallgaeu",
      "act": "traffic_order",
      "basis": "StVO/45/1/7/b"
    },
    {
      "actor": "authority:state_building_office_kempten",
      "act": "construction_or_project_consent",
      "basis": "BayStrWG/44",
      "unless": [
        "transferred_power_under_BayStrWG_58_4",
        "special_project_burden_under_BayStrWG_44"
      ]
    }
  ],
  "decision_chain": [
    "BayStrWG/58/4: transfer of road authority powers negotiable, never unilateral",
    "StVO/45/1/7/b: cycle lane areas orderable where traffic flow and safety allow",
    "StVO/45/1j: city may apply formally, no right to approval",
    "BayStrWG/44: rebuilding the state carriageway needs consent or a project agreement"
  ],
  "legal_thresholds": [
    "traffic_flow_considered",
    "traffic_safety_not_impaired",
    "area_for_walking_and_cycling_is_appropriate"
  ],
  "open_facts": [
    "existing_art_58_4_agreement",
    "existing_art_44_agreement",
    "exact_lateral_boundary",
    "component_specific_burden",
    "parcel_ownership"
  ],
  "sources": [
    "BayStrWG/58/4",
    "BayStrWG/44",
    "StVO/45/1/7/b",
    "StVO/45/1j",
    "case:buchloe-bahnhofstrasse-st2035 (as_of 2026-08-21)"
  ],
  "confidence": "medium"
}
```

Pflichtfelder je Antwortobjekt: `result` (Enum: feasible, conditionally_feasible, infeasible, unresolved), die Rollen des fragenden Actors, `cannot_unilaterally`, `required_decisions` mit Actor, Handlung, Normbasis und Ausnahmen (`unless`), `decision_chain` als geordnete Ableitungsschritte mit Regel- oder Norm-ID je Schritt, `legal_thresholds`, `open_facts` (die unknowns des Casefiles; das Exzerpt-Beispiel nannte davon abweichende Begriffe, die der RFC auf die Casefile-IDs normiert), `confidence` und `sources` (Norm-IDs plus Casefile-ID mit Zeitstand). Das Exzerpt fordert für jeden Output Schlussfolgerung, Entscheidungskette, offene Tatsachen und Quellen; `result`, `decision_chain`, `open_facts` und `sources` setzen das um. Jedes Feld verweist auf Norm-IDs der Schicht 1, Fakten des Casefiles oder im Exzerpt benannte Stellen; die Actor-IDs des Landratsamts und des Bauamts stehen im Exzerpt-Text und werden in Phase 1 als Actor-Objekte ins Casefile übernommen. `confidence` ist im MVP grob dreistufig (hoch, mittel, niedrig) und nicht numerisch kalibriert; die Zuweisungsregel steht in OF-7. Ein Boolescher Wert ist keine zulässige Antwort (P1).

## 8. Pilot: Art. 58 Abs. 4 BayStrWG

Regel in Datalog-artiger Form:

```prolog
eligible_art58_4(City, Road) :-
    located_in(Road, City),
    road_class(Road, state_road),
    ortsdurchfahrt(Road),
    binding_census_population(City, Population),
    Population > 9000,
    Population =< 25000.

legal_lever(City, Road, transfer_road_authority_powers) :-
    eligible_art58_4(City, Road).

requires(
    transfer_road_authority_powers,
    agreement(road_authority(Road), City)
).

decision_mode(
    transfer_road_authority_powers,
    negotiated_discretion
).

possible_scope(
    transfer_road_authority_powers,
    partial_or_total
).

not_automatically_implied(
    transfer_road_authority_powers,
    transfer_of_road_construction_burden
).

not_automatically_implied(
    transfer_road_authority_powers,
    transfer_of_stvo_authority
).
```

Darüber eine Elixir-DSL:

```elixir
norm "BayStrWG/58/4",
  # Inkrafttreten und Abrufdatum sind im Exzerpt nicht belegt; beides ist vor
  # der Umsetzung zu recherchieren (OF-2, OF-5). Die DSL muss fehlende Kenntnis
  # ausdrücken können, statt sie zu simulieren (P2).
  valid_from: :unresearched,
  source: [url: "https://www.gesetze-bayern.de/Content/Document/BayStrWG-58"],
  jurisdiction: :bavaria do

  applies_when road.class == :state_road
  applies_when road.context == :ortsdurchfahrt

  applies_when city.binding_census_population in 9_001..25_000

  enables :road_authority,
    action: {:transfer, :road_authority_powers},
    to: :municipality,
    via: :agreement,
    scope: [:partial, :total]

  decision_mode :negotiated_discretion

  does_not_automatically_imply [
    :transfer_of_road_construction_burden,
    :transfer_of_stvo_authority,
    :transfer_of_property
  ]
end
```

Das Exzerpt-Beispiel trug hier valid_from: ~D[2026-01-01], ohne das Inkrafttreten zu belegen; der RFC ersetzt es durch :unresearched und bindet die Normquelle (P5). Der Datenbestand simuliert keine Kenntnis, die niemand geprüft hat (P2). Abnahmekriterium des Pilots sind die Grenzfalltests:

```elixir
test "9000 Einwohner reichen nicht"
test "9001 Einwohner reichen"
test "25000 Einwohner reichen"
test "25001 Einwohner reichen nicht"
test "freie Strecke ist keine Ortsdurchfahrt"
test "Kreisstraße fällt nicht unter diese konkrete Regel"
```

Diese sechs Tests sind das alleinige Abnahmekriterium der Phase 1. Die kontraktkonforme Antwort auf die Radfahrstreifen-Frage aus Abschnitt 7, erzeugt aus der Kombination von Art. 58 Abs. 4, Art. 44 BayStrWG und § 45 StVO, wird Abnahmekriterium der Phase 2 — erst wenn sie ohne manuelle Nacharbeit funktioniert, ist die Generalisierung über die Pilotnorm hinaus bewiesen.

## 9. Unbestimmte Rechtsbegriffe als Prüfobjekte

Ausdrücke wie „erheblich breiter", „angemessene Flächen", „Sicherheit und Leichtigkeit des Verkehrs", „überwiegende Gründe des öffentlichen Wohls", „wesentliche Änderung" dürfen nicht durch ein LLM mit `true` oder `false` belegt werden (P3). Sie erscheinen als eigene Prüfobjekte:

```yaml
assessment:
  term: substantially_wider
  norm: BayStrWG/42/3
  decision_actor: road_authority_or_government
  required_evidence:
    - surveyed_cross_section
    - functional_width_analysis
    - traffic_forecast
  outcome: offen
```

Prüfobjekte tragen nicht den epistemischen Status der Fakten (Abschnitt 5), sondern ein eigenes Ergebnisfeld (offen, belegt, nicht belegt). Das Exzerpt notierte hier status: unresolved, ein Wert ausserhalb des Statusraums der Fakten; der RFC führt deshalb ein eigenes Feld. Erst das Ergebnis einer abgeschlossenen Prüfung wird als neue Fact mit epistemic_status in das Casefile übernommen. Das System kann Beweise sammeln, Argumente zuordnen und eine Prognose bilden. Die rechtlich zuständige Stelle bleibt aber als Entscheider sichtbar; das System trifft die Entscheidung nicht (P4).

## 10. Umsetzung im Repo (Vorschlag)

- **Neues Tool `apps/rechtslage`** (Arbeitstitel, GO entscheidet den Namen): Elixir-first (Repo-Prinzip 1), Workspace-Mitglied wie ratsinfo und ratsprojekte.
- **AI-Schnittstellen** (Repo-Prinzip 5): CLI zuerst, `rechtslage ask "…"` und `rechtslage explain BayStrWG/58/4`; später ein read-only MCP-Server mit ask, explain und levers.
- **Unix-Prinzip** (Repo-Prinzip 2): rechtslage kennt ratsinfo und ratsprojekte nicht. Die Werkzeuge treffen sich in der AI-Session, nie im Code.
- **Phasierung:**
  - Phase 1 (MVP): vom Objektmodell die 16 Objekte, die Pilot und Antwortobjekt ausüben (alles ausser Procedure; Evidence ist für die Prüfobjekte in Abschnitt 9 nötig; Festlegung als Vorschlag, das GO entscheidet den Schnitt), von den Modalitäten may_decide, may_apply, may_agree, requires_consent und has_claim als Negation (must_decide, must_agree, must_hear, may_plan, must_reclassify folgen mit den Phase-2-Normen); Pilotregel 58 Abs. 4 mit sechs Grenzfalltests grün; `ask` mit Antwortobjekt; alles dateibasiert.
  - Phase 2: weitere Normen des Exzerpts nachmodellieren (Auswahl, u. a. Art. 42 Abs. 1 und Abs. 3, Art. 18, Art. 24, Art. 35, Art. 38 Abs. 1, Art. 48, Art. 7, Art. 9 Abs. 4 BayStrWG, Art. 13f BayFAG, Art. 44 BayStrWG, § 45 StVO); Abnahmekriterium ist die kontraktkonforme Radfahrstreifen-Antwort aus Abschnitt 7 (Art. 58 Abs. 4, Art. 44 BayStrWG, § 45 StVO). Hebel-Abfrage „Welche Hebel hat die Stadt für X?".
  - Phase 3: Faktenkarte Bahnhofstrasse, Geodaten, gegebenenfalls PostGIS; Provenienz nach PROV-O.

## 11. Offene Fragen

- **OF-1 Datalog-Kern.** Die Recherche vom 2026-09-03 (docs/rechtsgrundlagen/recherche-datalog-engines.md) empfiehlt für den Pilot den Eigenbau: ein semi-naiver Interpreter in purem Elixir für positive Horn-Klauseln ohne Negation, geschätzt 200 bis 400 Zeilen, wenige fokussierte Tage Aufwand für eine BEAM-erfahrene Person. Positive Klauseln sind monoton, die Fixpunkt-Iteration terminiert ohne Stratifikation (Abiteboul/Hull/Vianu, Foundations of Databases, 1995, Kap. 9). Begründung: In Elixir/Erlang existiert keine gepflegte Datalog- oder Logikbibliothek (einziges hex-Paket `datalog` seit 2019 dorm, Recherchelage L1). Die Rust-Crates sind tot (`datalog`, Stand 2017) oder am Pilot vorbeigeplant (nemo mit RDF-Schwerpunkt, datafrog low-level, egglog, cozo, crepe mit anderer Zielsetzung) und brächten eine zweite Toolchain ins Homelab. Soufflé (Lizenz UPL, Release 2.5 vom 03/2025) ist die einzige produktionsreife Engine, aber ohne natives JSON (Exportformate CSV/TSV/rfc4180/SQLite/Terminal), mit Fremd-Binary und einem offenen ARM-Concurrency-Issue (#2476), das bei Apple Silicon gegen Soufflé spricht. Soufflé ist damit kein geplanter Fallback: Kommen Negation, tiefe Rekursion oder grosse Faktbestände dazu, steht ohnehin eine neue Engine-Entscheidung an, die die Plattform einbeziehen muss. Vorbehalte der Recherche, alle fünf: eine gepflegte Logikbibliothek unter anderem Namen ist nicht vollständig ausgeschlossen (L1), NIF-Aufwand nur geschätzt (L2), Soufflé auf macOS/ARM nicht verifiziert (L3), Pflegezustand von LegalRuleML/Akoma-Ntoso nur nach letztem Push-Datum beurteilt (L4, relevant für die Ausbaustufen in Abschnitt 6), nemo/datafrog als NIF-Basis nicht über „Rust-Lib vorhanden" hinaus geprüft (L5). Die Entscheidung bleibt beim GO.
- **OF-2 Normenbeschaffung.** Wie kommen BayStrWG- und StVO-Texte versioniert und absatzgenau ins Repo? Manuell für den Pilot. Eine Scraping-Pipeline für gesetze-bayern.de wäre ein eigenes Tool (Unix-Prinzip) mit eigener Urheberrechtsprüfung.
- **OF-3 Ablage der Normquellen.** Format: Markdown mit Frontmatter gegen Akoma Ntoso von Anfang an. Ort: `docs/normen/` gegen ein Tool-Datenverzeichnis in `apps/rechtslage`.
- **OF-4 Verhältnis zu ratsprojekte.** rechtslage liefert Hebel-Analysen als Arbeitsgrundlage für Realisierungsstränge. Nutzung read-only über die AI-Session, keine Datenmodell-Kopplung.
- **OF-5 Normänderungen.** Erkennung und Versionierung von Gesetzesänderungen: valid_from/valid_to je Norm, Zeitstand je Anfrage, Benachrichtigung bei Änderung.
- **OF-6 Namenskonvention der Atome.** Deutsche Fachbegriffe (erheblich_breiter) oder englische Kernels (substantially_wider). Das Exzerpt nutzt beides; vor der ersten Implementierung ist eine Konvention festzulegen.
- **OF-7 Epistemische Vererbung und Kalibrierung.** Wie Regeln den Status ihrer Prämissen vererben und wie confidence zugewiesen wird, ist vor der Implementierung festzulegen. MVP-Annahme dieses RFC: Eine Ableitung übernimmt den schwächsten Status ihrer Prämissen; confidence ist grob dreistufig (hoch nur ohne offene Fakten und ausschliesslich mit verifizierten Prämissen, mittel bei asserted-Prämissen oder offenen Fakten, niedrig wenn zentrale Fakten unknown oder disputed sind). Beides ist an den Grenzfalltests mitzuprüfen.

## 12. Grenzen und Quellen

Grenzen:

- Kein Rechtsrat. Ausgaben sind Arbeitsgrundlagen für Stadtrat und Verwaltung, keine verbindliche Auslegung (P4).
- Ein Pilot belegt die Machbarkeit für eine Normklasse, nicht die Generalisierung. Rekursion, Negation und Normkonflikte sind unbelegt.
- Die Normtexte wurden im Exzerpt nicht wortlautnah abgeglichen; vor jeder Umsetzung sind die Absatztexte gegen die amtlichen Quellen zu verifizieren (P5).
- Die Quellenpflicht (P5) ist im heutigen Material nicht erfüllt: Die 18 Fussnoten des Exzerpts sind Links ohne erfasste Abrufdaten, das Casefile bindet Quellen nur über source_type- und source_status-Marker. P5 beschreibt den Zielzustand des Systems (Normierung in Abschnitt 5 und Abschnitt 8, Nachtrag der Abrufdaten bei der Übernahme in Schicht 1), nicht die heutige Grundlage.
- Diese Analysesession läuft im AI-Harness, dessen Risiken RFC 0001 beschreibt.

Quellen: docs/rechtsgrundlagen/exzerpt.md mit 18 Quellenlinks (Gesetze Bayern, gesetze-im-internet, Statistik Bayern, Staatliches Bauamt Kempten, FNP-Entwurf Buchloe, OASIS LegalDocML); AGENTS.md Prinzipien 1 bis 7; RFC 0001 für die RFC-Konvention und den Harness-Kontext (derzeit uncommitteter Entwurf im Worktree threat-modelling).
