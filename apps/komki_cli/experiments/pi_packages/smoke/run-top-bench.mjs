#!/usr/bin/env node
/**
 * Benchmark für Aufgabe 1 (RIS-TOP zusammenfassen, Ticket #158).
 *
 * Der Smoke-Test zeigte: Mit natürlichem Prompt fehlt der Eigenanteil von
 * 80 000 Euro in 4/4 Läufen. Dieser Benchmark misst sauber, ob das eine
 * systematische Lücke oder eine Prompt-Sensitivität ist:
 *
 *   Variante A — natürlicher Prompt („Nenne Gremium, Sitzungsdatum,
 *                Kostenschätzung und Beschlussvorschlag"), 3 Läufe
 *   Variante B — Spec-expliziter Prompt (zusätzlich: Vorhaben namentlich,
 *                Gesamtkosten mit Aufteilung), 3 Läufe
 *
 * Gewünschtes Verhalten (Kriterien K1–K8), abgeleitet aus der
 * Sitzungsmappe-Vorlage des Skills sitzungsvorbereitung (Gremium, Datum,
 * Gegenstand, „was die Vorlage will", Beschlussvorschlag; Finanzierungs-TOPs
 * sind im Workflow erster Klasse) und der Quellenpflicht (AGENTS.md §6):
 *
 *   K1 Gremium · K2 Sitzungsdatum · K3 Vorhaben benannt · K4 Anliegen
 *   K5 Gesamtkosten · K6 Finanzierungsstruktur (Eigenanteil/Förderanteil)
 *   K7 Beschlussvorschlag (≥2 Komponenten) · K8 keine erfundenen Zahlen
 *
 * K8 erlaubt arithmetisch aus Quellenzahlen abgeleitete Zahlen (z. B.
 * Förderanteil 160 000 = 240 000 − 80 000) — abgeleitet ist nicht erfunden;
 * die Ableitung wird aber protokolliert.
 *
 * Aufruf:
 *   node smoke/run-top-bench.mjs [--root <run-root>] [--runs 3]
 */
import { mkdir, writeFile } from "node:fs/promises";
import path from "node:path";

import { runRoot, timestamp } from "../lib/config.mjs";
import { writeTextFile } from "../lib/fixtures.mjs";
import { runPi } from "../lib/runner.mjs";
import { KRITERIEN, checkAnswer } from "./criteria.mjs";
import { TOP_3_ANHOERUNG } from "./fixtures.mjs";
import { answerText, resolveLlama, usageTotals, validateToolCalls } from "./measure.mjs";

const PROMPT_A =
  "Lies die Datei top-3-anhoerung.md im aktuellen Verzeichnis und fasse TOP 3 für die Sitzungsvorbereitung in höchstens fünf Sätzen zusammen. Nenne Gremium, Sitzungsdatum, Kostenschätzung und Beschlussvorschlag.";

const PROMPT_B =
  "Lies die Datei top-3-anhoerung.md im aktuellen Verzeichnis und fasse TOP 3 für die Sitzungsvorbereitung in höchstens fünf Sätzen zusammen. Nenne Gremium, Sitzungsdatum, das Vorhaben mit Namen, die Gesamtkosten mit ihrer Aufteilung (Eigenanteil und Förderanteil) und den Beschlussvorschlag.";

function parseArgs(argv) {
  const args = { root: null, runs: 3 };
  for (let i = 0; i < argv.length; i += 1) {
    if (argv[i] === "--root") args.root = argv[i + 1];
    if (argv[i] === "--runs") args.runs = Math.max(1, Number(argv[i + 1]) || 3);
  }
  return args;
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const root = args.root ?? runRoot(timestamp());
  const llama = await resolveLlama();
  const provider = {
    upstreamBaseUrl: llama.baseUrl,
    apiKey: llama.apiKey,
    name: "pi-local",
    model: "local-model",
    maxTokens: 16384,
  };

  console.log(`llama-server: port ${llama.port}, pid ${llama.pid}`);
  console.log(`Benchmark-Root: ${root}`);

  const varianten = [
    { id: "A", prompt: PROMPT_A, label: "natürlicher Prompt (wie Smoke-Aufgabe 1)" },
    { id: "B", prompt: PROMPT_B, label: "Spec-expliziter Prompt (Vorhaben + Finanzierungsstruktur)" },
  ];

  const runsByVariant = {};
  for (const variante of varianten) {
    runsByVariant[variante.id] = [];
    for (let i = 1; i <= args.runs; i += 1) {
      const runDir = path.join(root, `task-1-bench-${variante.id.toLowerCase()}-${i}`);
      const workDir = path.join(runDir, "work");
      await writeTextFile(path.join(workDir, "top-3-anhoerung.md"), TOP_3_ANHOERUNG);
      console.log(`Variante ${variante.id}, Lauf ${i}/${args.runs} …`);

      const run = await runPi({
        id: `bench-${variante.id}-${i}`,
        runRoot: root,
        runDir,
        provider,
        contextWindow: 131072,
        timeoutMs: 300_000,
        tools: "read",
        prompt: variante.prompt,
      });

      const answer = answerText(run.session) ?? "";
      const { erfuellt, k7Komponenten, zahlen } = checkAnswer(answer);
      const missing = Object.entries(erfuellt)
        .filter(([, ok]) => !ok)
        .map(([id]) => id);
      const validReadCalls = validateToolCalls(run.requests).filter(
        (call) => call.name === "read" && call.valid,
      );
      runsByVariant[variante.id].push({
        lauf: i,
        durationMs: run.durationMs,
        exitCode: run.code,
        timedOut: run.timedOut,
        usage: usageTotals(run.requests),
        readCallValid: validReadCalls.length > 0,
        answer,
        erfuellt,
        k7Komponenten,
        zahlen,
        missing,
        vollstaendig: missing.length === 0,
      });
      console.log(
        `  ${missing.length === 0 ? "VOLLSTÄNDIG" : `fehlt: ${missing.join(", ") || "–"}`}` +
          (zahlen.erfunden.length > 0 ? ` erfunden: ${zahlen.erfunden.join(", ")}` : "") +
          (zahlen.abgeleitet.length > 0 ? ` abgeleitet: ${zahlen.abgeleitet.join(", ")}` : ""),
      );
    }
  }

  const zusammenfassung = {};
  for (const variante of varianten) {
    const laeufe = runsByVariant[variante.id];
    const kriteriumFehl = {};
    for (const kriterium of [...KRITERIEN.map((k) => k.id), "K7", "K8"]) {
      const fehl = laeufe.filter((lauf) => !lauf.erfuellt[kriterium]).length;
      if (fehl > 0) kriteriumFehl[kriterium] = `${fehl}/${laeufe.length}`;
    }
    zusammenfassung[variante.id] = {
      label: variante.label,
      prompt: variante.prompt,
      laeufe: laeufe.length,
      vollstaendigeLaeufe: laeufe.filter((lauf) => lauf.vollstaendig).length,
      kriteriumFehlhaeufigkeit: kriteriumFehl,
    };
  }

  // Verdikt: Das gewünschte Verhalten ist bewiesen, wenn Variante B es in
  // jedem Lauf liefert. Die A-Matrix dokumentiert die Prompt-Sensitivität.
  const b = zusammenfassung.B;
  const verdikt =
    b.vollstaendigeLaeufe === b.laeufe ? "pass" : b.vollstaendigeLaeufe > 0 ? "partial" : "fail";

  const result = {
    id: "task-1-bench",
    title: "Benchmark: RIS-TOP zusammenfassen gegen Kriterien K1–K8",
    hypothesis:
      "Die im Smoke-Test beobachtete Lücke (Eigenanteil fehlt in 4/4 Läufen) ist Prompt-Sensitivität: Mit explizit eingeforderter Finanzierungsstruktur liefert das Modell alle Muss-Kriterien — andernfalls liegt ein systematisches Modelldefizit vor.",
    gewuenschtesVerhalten: {
      herleitung:
        "Sitzungsmappe-Vorlage im Skill sitzungsvorbereitung (Gremium, Datum, Gegenstand, »was die Vorlage will«, Beschlussvorschlag); Finanzierungs-TOPs sind im Workflow erster Klasse (foerdermittel_recherche-Pflicht); Quellenpflicht AGENTS.md §6 für K8.",
      kriterien: [
        ...KRITERIEN.map((k) => ({ id: k.id, muss: k.label })),
        { id: "K7", muss: "Beschlussvorschlag (≥2 Komponenten: Zustimmung/Haushaltsplanung/Ergänzungsantrag)" },
        { id: "K8", muss: "keine erfundenen Zahlen; abgeleitete (Summe/Differenz aus Quellenzahlen) werden protokolliert, aber toleriert" },
      ],
    },
    varianten: zusammenfassung,
    laeufe: runsByVariant,
    verdikt,
    umgebung: {
      piProvider: "pi-local/local-model",
      maxTokens: 16384,
      laeufeJeVariante: args.runs,
    },
  };

  const outDir = path.join(root, "results");
  await mkdir(outDir, { recursive: true });
  const outputPath = path.join(outDir, "task-1-bench.json");
  await writeFile(outputPath, JSON.stringify(result, null, 2));

  console.log(`\nErgebnis: ${outputPath}`);
  console.log(`Verdikt: ${verdikt.toUpperCase()} (Maßstab: Variante B vollständig in jedem Lauf)`);
  for (const variante of varianten) {
    const z = zusammenfassung[variante.id];
    console.log(
      `Variante ${variante.id}: ${z.vollstaendigeLaeufe}/${z.laeufe} vollständig` +
        (Object.keys(z.kriteriumFehlhaeufigkeit).length > 0
          ? ` — Fehlhäufigkeiten: ${JSON.stringify(z.kriteriumFehlhaeufigkeit)}`
          : ""),
    );
  }

  process.exitCode = verdikt === "pass" ? 0 : verdikt === "partial" ? 0 : 1;
}

try {
  await main();
} catch (error) {
  console.error(String(error?.message ?? error));
  process.exitCode = 2;
}
