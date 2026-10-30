/**
 * Schreibt skills/<name>/BENCHMARK.md aus dem Ergebnis einer Messung
 * (Ticket #292). Der Bericht nennt Rohzählungen — x von Läufen je Arm und
 * Kriterium — und keine „belegt“-Formeln; jede Zahl ist über die Suite
 * (Fälle, Bewerter, Bedingungen) und den Modell-Pin nachrechenbar.
 */

function sekunden(ms) {
  if (ms === null || ms === undefined) return "–";
  const s = Math.round(ms / 100) / 10;
  return `${s.toLocaleString("de-DE")} s`;
}

function zahl(n) {
  if (n === null || n === undefined) return "–";
  return String(n);
}

function zaelung(bestanden, gesamt) {
  return `${bestanden}/${gesamt}`;
}

/** Kriterien-Liste je Kriterium, Spalten je Arm. */
function kriterienTabelle(fall, armLabel) {
  const lines = [];
  const kopf = ["Kriterium (Bewerter)"];
  for (const arm of fall.arme) kopf.push(armLabel[arm] ?? arm);
  lines.push(`| ${kopf.join(" | ")} |`);
  lines.push(`|${kopf.map(() => "---").join("|")}|`);
  for (const bewerter of fall.bewerterListe) {
    const reihe = [`**${bewerter.id}** (${bewerter.typ})`];
    for (const arm of fall.arme) {
      const e = fall.ergebnisse[arm];
      const n = e?.jeKriterium[bewerter.id]?.bestanden ?? 0;
      const gesamt = e?.laeufeGesamt ?? 0;
      reihe.push(zaelung(n, gesamt));
    }
    lines.push(`| ${reihe.join(" | ")} |`);
  }
  return lines.join("\n");
}

/** „id x/N“ für jedes Kriterium mit mindestens einem Fehlschlag im Arm. */
function fehlkriterienText(e) {
  const fehl = [];
  for (const [id, eintrag] of Object.entries(e.jeKriterium)) {
    if (eintrag.bestanden < e.laeufeGesamt) fehl.push(`${id} ${eintrag.bestanden}/${e.laeufeGesamt}`);
  }
  return fehl.length > 0 ? fehl.join(" · ") : "keine";
}

export function berichtMarkdown(daten) {
  const {
    skillName,
    datum,
    rahmen,
    arme,
    armLabel,
    faelle,
    nichtGemessen,
    notizen,
    reproduktion,
    suiteSha,
  } = daten;

  const lines = [];
  lines.push(`# Benchmark: ${skillName}`);
  lines.push("");
  lines.push(
    `Gemessen am ${datum} gegen das Zielmodell der komki-Instanz. Alle Zahlen sind` +
      ` Rohzählungen über die gelaufenen Läufe; nichts davon „belegt“ einen Nutzen für sich` +
      ` allein — gezählt wird, was zählbar ist. Fälle, Fixtures und Bewerter stehen` +
      ` versioniert in [\`evals/\`](evals/) (Suite-Stand: \`${suiteSha}\`); jede Änderung an` +
      ` einem Kriterium setzt die Vergleichsreihe zurück und gehört in denselben Commit.`,
  );
  lines.push("");
  lines.push("## Rahmen");
  lines.push("");
  lines.push("| Feld | Wert |");
  lines.push("|---|---|");
  lines.push(`| Modell | ${rahmen.modell} |`);
  lines.push(`| GGUF | \`${rahmen.gguf}\` · sha256 \`${rahmen.ggufSha256}\` |`);
  lines.push(
    `| Sampling (Server-Defaults, pro Request nicht überschrieben) | ${rahmen.sampling} |`,
  );
  lines.push(`| llama-server | ${rahmen.server} |`);
  lines.push(`| pi · Node | ${rahmen.pi} · ${rahmen.node} |`);
  lines.push(`| Kontext · maxTokens | ${zahl(rahmen.ctx)} · ${zahl(rahmen.maxTokens)} |`);
  lines.push(`| Läufe pro Arm | ${rahmen.laeufeJeArm} |`);
  lines.push(`| Arme je Runde abwechselnd | ja (Lauf 1 aller Arme, dann Lauf 2, …) |`);
  lines.push(
    `| Fremdlast (serverRequestCountMismatch) | ${rahmen.fremdlastLaeufe}/${rahmen.gesamtLaeufe} Läufe |`,
  );
  lines.push(`| Richter für llm-Kriterien | ${rahmen.richter} |`);
  lines.push("");

  const benutzteArme = [
    ...new Set(faelle.flatMap((fall) => (fall.typ === "verhalten" ? fall.arme : []))),
  ];
  if (benutzteArme.length > 0) {
    lines.push("## Arme (Verhaltensfälle)");
    lines.push("");
    lines.push("| Arm | Skill-Fassung | Zeilen | sha256 (Inhalt) | Herkunft |");
    lines.push("|---|---|---|---|---|");
    for (const arm of benutzteArme) {
      const pin = arme[arm];
      lines.push(
        `| **${armLabel[arm] ?? arm}** | ${pin.label} | ${pin.zeilen ?? "–"} | \`${pin.sha256 ?? "–"}\` | ${pin.herkunft} |`,
      );
    }
    lines.push("");
  }

  for (const fall of faelle) {
    lines.push(`## Fall: ${fall.id} (${fall.typ})`);
    lines.push("");
    lines.push(fall.beschreibung);
    lines.push("");
    lines.push(`> Prompt: „${fall.prompt}“`);
    if (fall.quelle) lines.push(`> Quelle des Falls: ${fall.quelle}`);
    if (fall.fixtures.length > 0) {
      lines.push(`> Fixtures (synthetisch): ${fall.fixtures.map((f) => `\`${f}\``).join(", ")}`);
    }
    if (fall.typ !== "verhalten") {
      lines.push(
        `> Arm: echte Skill-Auswahl über pis \`--skill\`-Mechanismus — alle ${fall.registrierteSkills} Skills registriert, kein Anhängen an den System-Prompt. Gemessen wird, ob der Skill per \`read\` geladen wird (Trigger) bzw. nicht geladen wird (Negativ).`,
      );
    }
    lines.push("");
    lines.push(kriterienTabelle(fall, armLabel));
    lines.push("");
    for (const arm of fall.arme) {
      const e = fall.ergebnisse[arm];
      if (!e) continue;
      const medianen = [`Median-Wandzeit: ${sekunden(e.medianWandzeitMs)}`];
      medianen.push(`Median Prompt-Tokens: ${zahl(e.medianPromptTokens)}`);
      medianen.push(`Median Completion-Tokens: ${zahl(e.medianCompletionTokens)}`);
      lines.push(
        `- **${armLabel[arm] ?? arm}** — ${medianen.join(" · ")} · Läufe mit Timeout/Fehler: ` +
          `${e.timeoutLaeufe + e.fehlerLaeufe}/${e.laeufeGesamt} · ungültige Tool-Calls: ${e.toolCallFehler}`,
      );
      lines.push(`  Fehlkriterien: ${fehlkriterienText(e)}`);
      if (e.geleseneSkills) {
        const counts = Object.entries(e.geleseneSkills)
          .sort((a, b) => b[1] - a[1])
          .map(([name, n]) => `${name} ${n}/${e.laeufeGesamt}`)
          .join(" · ");
        lines.push(`  Gelesene Skills je Lauf: ${counts || "–"}`);
      }
    }
    if ((fall.auffaelligkeiten ?? []).length > 0) {
      lines.push("");
      lines.push("Auffälligkeiten (automatisch gesammelt):");
      for (const eintrag of fall.auffaelligkeiten) lines.push(`- ${eintrag}`);
    }
    lines.push("");
    lines.push("Kriterien des Falls:");
    for (const bewerter of fall.bewerterListe) {
      lines.push(`- **${bewerter.id}** (${bewerter.typ}, \`${bewerter.quelle}\`): ${bewerter.text}`);
    }
    lines.push("");
  }

  if (notizen) {
    lines.push("## Stichproben-Notizen");
    lines.push("");
    lines.push(notizen.trim());
    lines.push("");
  }

  if ((nichtGemessen ?? []).length > 0) {
    lines.push("## Nicht gemessen");
    lines.push("");
    for (const eintrag of nichtGemessen) lines.push(`- ${eintrag}`);
    lines.push("");
  }

  lines.push("## Reproduktion");
  lines.push("");
  lines.push("```bash");
  lines.push(reproduktion);
  lines.push("```");
  lines.push("");
  return lines.join("\n");
}
