#!/usr/bin/env node
/**
 * Realmodell-Smoke-Test (Ticket #158): pi 1.4.0 + Gemma 4 26B (llama-server
 * der komki-Instanz) statt Mock-Provider.
 *
 * Aufgaben:
 *   1  RIS-TOP zusammenfassen (synthetisch, read-Tool)
 *   2  Quellen extrahieren (Quelle/Abrufdatum/Seite, read+write)
 *   3  Deutschen Text redigieren, ohne Fakten zu ändern (read+write)
 *   4  Todo-Workflow über mehrere Schritte inkl. --continue (rpiv-todo)
 *   6  Compaction-Experiment: deutsche Präferenz über die Standard-Compaction
 *      retten; misst Kosten und Verluste (pi-vcc-Vergleichsbasis)
 *
 * Aufgabe 5 (ask_user_question im TUI) läuft separat, weil sie tmux braucht:
 *   node smoke/run-tui.mjs --root <run-root>
 *
 * Der Lauf ersetzt keine Qualitätsbewertung des Modells; er misst, ob die
 * fünf Aufgaben laufen (oder welcher Fehler auftritt), plus Latenz,
 * Tool-Call-Fehler, Reparaturbedarf, Token und Speicher. Ergebnisse landen
 * unter <root>/results/*.json, <root>/results.json und <root>/SMOKE.md.
 */
import { mkdir, readFile, writeFile } from "node:fs/promises";
import path from "node:path";

import { PACKAGES, runRoot, packageDir, timestamp } from "../lib/config.mjs";
import { fillerBytes, writeTextFile } from "../lib/fixtures.mjs";
import { requirement } from "../lib/experiment.mjs";
import { runPi } from "../lib/runner.mjs";
import {
  answerText,
  llamaLogOffset,
  llamaLogSegment,
  llamaRssMiB,
  resolveLlama,
  sessionUsageTotals,
  summaryRequests,
  usageTotals,
  validateToolCalls,
} from "./measure.mjs";
import {
  ENTWURF_BESCHLUSSVORLAGE,
  LAGEBERICHT,
  NOTIZ_A,
  NOTIZ_B,
  NOTIZ_C,
  TOP_3_ANHOERUNG,
  missingFacts,
} from "./fixtures.mjs";

const TODO_EXTENSION = path.join(packageDir(PACKAGES.todo), "index.ts");

// Compaction-Erzwingung, angepasst an das echte Modell. Experiment 04 (Mock)
// nutzte contextWindow 1000 / reserve 100 / keep 50 — mit dem echten Server
// bricht das: pi klemmt max_completion_tokens auf
//   min(maxTokens, max(1, contextWindow − est(Kontext) − 4096))
// (CONTEXT_SAFETY_TOKENS = 4096, Schätzer chars/4; pi-Quelltext, gelesen
// am 30.10.2026), und bei W=1000 bleibt dabei genau 1 Token übrig — jede
// Antwort und die Summary brechen mit finishReason=length ab. Dimensionierung
// hier: 32-KB-Filler ≈ 8,2K Tokens + Hülle ≈ 9,5K est → Trigger bei
// est > 16384 − 8192; nach der Compaction bleibt est ≈ 10K →
// Output-Budget ≈ 2,3K Tokens (Antwort möglich). Der Tool-Result überlebt
// als ganzer Eintrag im Keep-Schwanz (Beobachtung, siehe Labbook).
const TINY = {
  compaction: { enabled: true, reserveTokens: 8192, keepRecentTokens: 512 },
};

/**
 * Verdikt mit Zwischenstufe: fail schlägt alles, partial wird im Gegensatz
 * zu verdictOf aus lib/experiment.mjs nicht zu pass aufgewertet.
 */
function smokeVerdict(requirements) {
  const gating = requirements.filter((r) => r.gating ?? true);
  if (gating.length === 0) return "not-tested";
  if (gating.some((r) => r.status === "fail")) return "fail";
  if (gating.some((r) => r.status === "partial" || r.status === "not-tested")) return "partial";
  return "pass";
}

/** Grobe Spracherkennung für Summary/Antworten (de/en/unbekannt). */
function detectLanguage(text) {
  if (!text) return null;
  const german = (text.match(/\b(der|die|das|und|nicht|für|wird|Sätze|Quelle|gelesen|Zusammenfassung)\b/gi) ?? []).length;
  const english = (text.match(/\b(the|and|for|with|was|read|summary|file|sources?|sentences?)\b/gi) ?? []).length;
  if (german === 0 && english === 0) return "unbekannt";
  return german >= english ? "de" : "en";
}

function parseArgs(argv) {
  const args = { only: null, root: null };
  for (let i = 0; i < argv.length; i += 1) {
    if (argv[i] === "--only") args.only = new Set((argv[i + 1] ?? "").split(",").filter(Boolean));
    if (argv[i] === "--root") args.root = argv[i + 1];
  }
  return args;
}

function selectTask(only, key) {
  return !only || only.has(key) || only.has(String(key));
}

/** Eine pi-Invocation mit Log-Grenzen und RSS-Drumherum. */
async function executeRun(llama, provider, options) {
  const logStart = await llamaLogOffset(llama);
  const rssBefore = llamaRssMiB(llama.pid);
  const run = await runPi(options);
  const logEnd = await llamaLogOffset(llama);
  return {
    run,
    serverRequests: await llamaLogSegment(llama, logStart, logEnd),
    rssBeforeMiB: rssBefore,
    rssAfterMiB: llamaRssMiB(llama.pid),
  };
}

/** Messwerte einer pi-Invocation (Proxy-Log, Session, llama-Log). */
function measurementsOf(executed) {
  const { run, serverRequests, rssBeforeMiB, rssAfterMiB } = executed;
  const toolCalls = validateToolCalls(run.requests);
  return {
    durationMs: run.durationMs,
    timedOut: run.timedOut,
    exitCode: run.code,
    stderrTail: (run.stderr ?? "").slice(-1500),
    eventCounts: Object.fromEntries(
      Object.entries(
        (run.events ?? []).reduce((acc, event) => {
          acc[event.type] = (acc[event.type] ?? 0) + 1;
          return acc;
        }, {}),
      ).map(([type, count]) => [type, count]),
    ),
    proxyRequests: run.requests.map((request) => ({
      url: request.url,
      status: request.status,
      durationMs: request.durationMs,
      finishReason: request.response?.finishReason ?? null,
      usage: request.response?.usage ?? null,
    })),
    usageProxy: usageTotals(run.requests),
    usageSession: sessionUsageTotals(run.session),
    serverRequests,
    rssLlamaMiB: { before: rssBeforeMiB, after: rssAfterMiB },
    toolCalls,
    toolCallErrorCount: toolCalls.filter((call) => !call.valid).length,
    lengthClampedRequests: run.requests
      .filter((request) => request.response?.finishReason === "length")
      .map((request) => ({
        durationMs: request.durationMs,
        maxCompletionTokens: request.parsed?.max_completion_tokens ?? null,
        completionTokens: request.response?.usage?.completion_tokens ?? null,
      })),
    sessionToolResults: (run.session?.toolResults ?? []).map((result) => ({
      toolName: result.toolName,
      isError: result.isError,
      text: result.text.slice(0, 300),
    })),
    answerText: answerText(run.session),
    sessionFile: run.sessionFile,
  };
}

// ---------------------------------------------------------------- Aufgabe 1

async function task1Top(llama, provider) {
  const runDir = path.join(ROOT, "task-1-top");
  const workDir = path.join(runDir, "work");
  await writeTextFile(path.join(workDir, "top-3-anhoerung.md"), TOP_3_ANHOERUNG);

  const executed = await executeRun(llama, provider, {
    id: "task-1",
    runRoot: ROOT,
    runDir,
    provider,
    contextWindow: 131072,
    timeoutMs: 300_000,
    tools: "read",
    prompt:
      "Lies die Datei top-3-anhoerung.md im aktuellen Verzeichnis und fasse TOP 3 für die Sitzungsvorbereitung in höchstens fünf Sätzen zusammen. Nenne Gremium, Sitzungsdatum, Kostenschätzung und Beschlussvorschlag.",
  });
  const m = measurementsOf(executed);
  const answer = m.answerText ?? "";

  const factGroups = [
    { label: "Kostenschätzung 240.000", options: ["240.000", "240000", "240 000", "240 Tausend"] },
    { label: "Eigenanteil 80.000", options: ["80.000", "80000", "80 000", "80 Tausend"] },
    { label: "Sitzungsdatum", options: ["12.11.2026", "12. November 2026", "12. November"] },
    { label: "Gremium", options: ["Ausschuss"] },
    { label: "Vorhaben", options: ["Bahnhofstraße"] },
  ];
  const missing = factGroups.filter(
    (group) => !group.options.some((option) => answer.includes(option)),
  );
  const readCalls = m.toolCalls.filter((call) => call.name === "read" && call.valid);

  const requirements = [
    requirement(
      "run-complete",
      "Lauf endet fehlerfrei (Exit 0, kein Timeout)",
      m.exitCode === 0 && !m.timedOut ? "pass" : "fail",
      { exitCode: m.exitCode, timedOut: m.timedOut, stderrTail: m.stderrTail },
    ),
    requirement(
      "read-tool-call",
      "Modell ruft read mit gültigen Argumenten auf",
      readCalls.length > 0 ? "pass" : "fail",
      { readCalls: readCalls.length, allCalls: m.toolCalls.map((c) => ({ name: c.name, class: c.class })) },
    ),
    requirement(
      "summary-facts",
      "Zusammenfassung nennt alle Kerntatsachen",
      missing.length === 0 ? "pass" : missing.length <= 1 ? "partial" : "fail",
      { missing: missing.map((group) => group.label), answer },
    ),
  ];

  return {
    id: "task-1-top",
    title: "RIS-TOP zusammenfassen (synthetisch, read-Tool)",
    hypothesis:
      "Gemma 4 26B ruft read mit korrekten Argumenten auf und fasst den synthetischen TOP mit allen Kerntatsachen in maximal fünf Sätzen zusammen.",
    measurements: m,
    requirements,
    verdict: smokeVerdict(requirements),
  };
}

// ---------------------------------------------------------------- Aufgabe 2

async function task2Quellen(llama, provider) {
  const runDir = path.join(ROOT, "task-2-quellen");
  const workDir = path.join(runDir, "work");
  await writeTextFile(path.join(workDir, "lagebericht-bahnhofstr.md"), LAGEBERICHT);

  const executed = await executeRun(llama, provider, {
    id: "task-2",
    runRoot: ROOT,
    runDir,
    provider,
    contextWindow: 131072,
    timeoutMs: 300_000,
    tools: "read,write",
    prompt:
      'Lies die Datei lagebericht-bahnhofstr.md im aktuellen Verzeichnis. Extrahiere alle Quellenangaben des Textes und schreibe sie als JSON-Array in die Datei quellen.json. Jedes Objekt erhält die Felder "Quelle" (Fundstelle, URL oder Bezeichnung), "Abrufdatum" (Datum aus dem Text, sonst null) und "Seite" (Seitenangabe aus dem Text, sonst null). Antworte am Ende nur mit einem Satz.',
  });
  const m = measurementsOf(executed);

  let parsed = null;
  let parseError = null;
  try {
    const raw = await readFile(path.join(workDir, "quellen.json"), "utf8");
    parsed = JSON.parse(raw);
  } catch (error) {
    parseError = String(error?.message ?? error);
  }
  const entries = Array.isArray(parsed) ? parsed : null;
  const keysOk =
    entries !== null &&
    entries.every(
      (entry) =>
        entry && typeof entry === "object" && "Quelle" in entry && "Abrufdatum" in entry && "Seite" in entry,
    );
  const withSeite = entries?.filter((entry) => entry.Seite !== null && entry.Seite !== undefined) ?? [];
  const withAbruf = entries?.filter((entry) => entry.Abrufdatum !== null && entry.Abrufdatum !== undefined) ?? [];
  const writeCalls = m.toolCalls.filter((call) => call.name === "write" && call.valid);

  const requirements = [
    requirement(
      "run-complete",
      "Lauf endet fehlerfrei (Exit 0, kein Timeout)",
      m.exitCode === 0 && !m.timedOut ? "pass" : "fail",
      { exitCode: m.exitCode, timedOut: m.timedOut, stderrTail: m.stderrTail },
    ),
    requirement(
      "write-tool-call",
      "Modell schreibt quellen.json über das write-Tool mit gültigen Argumenten",
      writeCalls.length > 0 ? "pass" : "fail",
      { writeCalls: writeCalls.length, allCalls: m.toolCalls.map((c) => ({ name: c.name, class: c.class })) },
    ),
    requirement(
      "quellen-json",
      "quellen.json existiert, ist ein JSON-Array mit Quelle/Abrufdatum/Seite je Objekt",
      parsed !== null && entries !== null && keysOk ? "pass" : "fail",
      { parseError, entryCount: entries?.length ?? 0, entries },
    ),
    requirement(
      "quellen-vollstaendig",
      "Mindestens vier Quellen, davon eine mit Seite und vier mit Abrufdatum",
      (entries?.length ?? 0) >= 4 && withSeite.length >= 1 && withAbruf.length >= 4 ? "pass" : "partial",
      { entryCount: entries?.length ?? 0, withSeite: withSeite.length, withAbruf: withAbruf.length },
    ),
  ];

  return {
    id: "task-2-quellen",
    title: "Quellen extrahieren (Quelle, Abrufdatum, Seite)",
    hypothesis:
      "Gemma 4 26B extrahiert die Quellenangaben aus dem deutschen Text in eine strukturierte JSON-Datei mit den drei Feldern, inklusive der bedingten Felder.",
    measurements: m,
    requirements,
    verdict: smokeVerdict(requirements),
  };
}

// ---------------------------------------------------------------- Aufgabe 3

async function task3Redigieren(llama, provider) {
  const runDir = path.join(ROOT, "task-3-redigieren");
  const workDir = path.join(runDir, "work");
  await writeTextFile(path.join(workDir, "entwurf-beschlussvorlage.md"), ENTWURF_BESCHLUSSVORLAGE);

  const executed = await executeRun(llama, provider, {
    id: "task-3",
    runRoot: ROOT,
    runDir,
    provider,
    contextWindow: 131072,
    timeoutMs: 300_000,
    tools: "read,write",
    prompt:
      "Lies die Datei entwurf-beschlussvorlage.md im aktuellen Verzeichnis. Redigiere den Text in eine neue Datei neue-fassung.md: deutlich kürzer, klare Sätze, aktive Form. Alle Fakten bleiben unverändert erhalten — Daten, Zahlen, Paragrafen, Fristen, Beträge, Hausnummern. Nichts hinzuerfinden. Antworte am Ende nur mit einem Satz.",
  });
  const m = measurementsOf(executed);

  let edited = null;
  let readError = null;
  try {
    edited = await readFile(path.join(workDir, "neue-fassung.md"), "utf8");
  } catch (error) {
    readError = String(error?.message ?? error);
  }

  const missing = edited !== null ? missingFacts(ENTWURF_BESCHLUSSVORLAGE, edited) : null;
  const originalWords = ENTWURF_BESCHLUSSVORLAGE.split(/\s+/).length;
  const editedWords = edited ? edited.split(/\s+/).length : 0;
  const shortened = edited !== null && editedWords <= Math.round(originalWords * 0.8);
  const writeCalls = m.toolCalls.filter((call) => call.name === "write" && call.valid);

  const requirements = [
    requirement(
      "run-complete",
      "Lauf endet fehlerfrei (Exit 0, kein Timeout)",
      m.exitCode === 0 && !m.timedOut ? "pass" : "fail",
      { exitCode: m.exitCode, timedOut: m.timedOut, stderrTail: m.stderrTail },
    ),
    requirement(
      "neue-fassung",
      "neue-fassung.md wurde über write erzeugt",
      edited !== null && writeCalls.length > 0 ? "pass" : "fail",
      { readError, writeCalls: writeCalls.length },
    ),
    requirement(
      "fakten-erhalten",
      "Alle Fakten (Zahlen, Daten, Paragrafen) sind unverändert erhalten",
      missing !== null && missing.length === 0 ? "pass" : missing !== null && missing.length <= 2 ? "partial" : "fail",
      { missingFacts: missing ?? [], originalWords, editedWords },
    ),
    requirement(
      "gekuerzt",
      "Die Redigierten Fassung ist deutlich kürzer (höchstens 80 % der Originallänge)",
      shortened ? "pass" : "partial",
      { originalWords, editedWords },
    ),
  ];

  return {
    id: "task-3-redigieren",
    title: "Deutschen Text redigieren, ohne Fakten zu ändern",
    hypothesis:
      "Gemma 4 26B glättet den behördendeutschen Entwurf in eine kürzere Fassung, ohne eine Zahl, ein Datum oder einen Paragrafen zu verändern.",
    measurements: m,
    requirements,
    verdict: smokeVerdict(requirements),
  };
}

// ---------------------------------------------------------------- Aufgabe 4

async function task4Todo(llama, provider) {
  const runDir = path.join(ROOT, "task-4-todo");
  const workDir = path.join(runDir, "work");
  for (const [name, content] of [
    ["notiz-a.md", NOTIZ_A],
    ["notiz-b.md", NOTIZ_B],
    ["notiz-c.md", NOTIZ_C],
  ]) {
    await writeTextFile(path.join(workDir, name), content);
  }

  const common = {
    runRoot: ROOT,
    runDir,
    provider,
    contextWindow: 131072,
    timeoutMs: 600_000,
    tools: "read,todo",
    extensions: [TODO_EXTENSION],
  };

  const executedA = await executeRun(llama, provider, {
    ...common,
    id: "task-4",
    prompt:
      "Du bereitest die Ausschusssitzung am 12.11.2026 vor (TOP 3 Bahnhofstraße). Im Verzeichnis liegen drei Notizen: notiz-a.md, notiz-b.md, notiz-c.md. Lege dir mit dem todo-Tool eine Aufgabenliste an (eine Aufgabe je Notiz plus eine Abschlussaufgabe). Arbeite sie ab: Lies jede Notiz und fasse ihre offene Frage in einem Satz zusammen; setze jede erledigte Aufgabe sofort auf completed. Zum Schluss stehen alle Aufgaben auf completed.",
  });
  const mA = measurementsOf(executedA);

  const executedB = await executeRun(llama, provider, {
    ...common,
    id: "task-4-continue",
    continue: true,
    prompt: "Liste deine Aufgaben mit dem todo-Tool und nenne zu jeder Aufgabe den Status.",
  });
  const mB = measurementsOf(executedB);

  const creates = mA.toolCalls.filter(
    (call) => call.name === "todo" && call.valid && call.args?.action === "create",
  );
  // create kann mehrere Aufgaben in einem Call anlegen (tasks-Array).
  const createdTasks = creates.reduce(
    (sum, call) => sum + (Array.isArray(call.args?.tasks) ? call.args.tasks.length : 1),
    0,
  );
  const updates = mA.toolCalls.filter(
    (call) => call.name === "todo" && call.valid && call.args?.action === "update",
  );
  const reads = mA.toolCalls.filter((call) => call.name === "read" && call.valid);

  const sessionStateA = (executedA.run.session?.customEntries ?? []).filter(
    (entry) => entry.customType === "rpiv-todo-state",
  );
  const sessionStateB = (executedB.run.session?.customEntries ?? []).filter(
    (entry) => entry.customType === "rpiv-todo-state",
  );
  const answerB = mB.answerText ?? "";
  const listResultB = [...mB.sessionToolResults].reverse().find((result) => result.toolName === "todo");
  const completedInB = listResultB ? (listResultB.text.match(/completed/g) ?? []).length : 0;

  const requirements = [
    requirement(
      "run-complete",
      "Beide Läufe enden fehlerfrei (Exit 0, kein Timeout)",
      mA.exitCode === 0 && !mA.timedOut && mB.exitCode === 0 && !mB.timedOut ? "pass" : "fail",
      { a: { exitCode: mA.exitCode, timedOut: mA.timedOut }, b: { exitCode: mB.exitCode, timedOut: mB.timedOut } },
    ),
    requirement(
      "todo-create",
      "Modell legt mindestens vier Aufgaben an (eine je Notiz plus Abschlussaufgabe)",
      createdTasks >= 4 ? "pass" : createdTasks > 0 ? "partial" : "fail",
      { createdTasks, creates: creates.map((call) => call.args), allTodoCalls: mA.toolCalls.filter((c) => c.name === "todo").map((c) => ({ class: c.class, args: c.args })) },
    ),
    requirement(
      "todo-update",
      "Modell setzt Aufgaben auf completed (update-Aufrufe vorhanden)",
      updates.length >= 3 ? "pass" : updates.length > 0 ? "partial" : "fail",
      { updates: updates.map((call) => call.args) },
    ),
    requirement(
      "notizen-gelesen",
      "Alle drei Notizen werden gelesen",
      reads.length >= 3 ? "pass" : reads.length > 0 ? "partial" : "fail",
      { reads: reads.map((call) => call.args) },
    ),
    requirement(
      "state-persistiert",
      "Session enthält rpiv-todo-state nach dem ersten Lauf",
      sessionStateA.length > 0 ? "pass" : "fail",
      { stateEntries: sessionStateA.map((entry) => entry.data) },
    ),
    requirement(
      "continue-liste",
      "Nach --continue listet das Modell die Aufgaben mit Status",
      sessionStateB.length > 0 && completedInB >= 3 ? "pass" : listResultB ? "partial" : "fail",
      { stateEntriesAfterContinue: sessionStateB.length, completedInList: completedInB, answerB, listResultText: listResultB?.text ?? null },
    ),
  ];

  return {
    id: "task-4-todo",
    title: "Todo-Workflow über mehrere Schritte (rpiv-todo, inkl. --continue)",
    hypothesis:
      "Gemma 4 26B orchestriert den Workflow mit dem todo-Tool über viele Schritte, persistiert den Zustand in der Session und listet ihn nach --continue mit Status.",
    measurements: { a: mA, b: mB },
    requirements,
    verdict: smokeVerdict(requirements),
  };
}

// ---------------------------------------------------------------- Aufgabe 6 (Sonde)

async function task6Compaction(llama, provider) {
  const runDir = path.join(ROOT, "task-6-compaction");
  const workDir = path.join(runDir, "work");
  await writeTextFile(path.join(workDir, "gross.txt"), fillerBytes(32 * 1024));

  const common = {
    runRoot: ROOT,
    runDir,
    provider,
    // Winziges Fenster erzwingt die Compaction (Dimensionierung siehe TINY).
    contextWindow: 16384,
    settings: TINY,
    timeoutMs: 600_000,
    tools: "read",
  };

  const executedA = await executeRun(llama, provider, {
    ...common,
    id: "task-6",
    prompt:
      "Merke dir für die gesamte Sitzung: Ich bevorzuge immer kurze Sätze und nenne bei jeder sachlichen Aussage die Quelle. Lies dann die Datei gross.txt im aktuellen Verzeichnis mit dem read-Tool und gib am Ende eine Zusammenfassung in drei Sätzen.",
  });
  const mA = measurementsOf(executedA);

  const executedB = await executeRun(llama, provider, {
    ...common,
    id: "task-6-continue",
    continue: true,
    prompt:
      "Ohne eine Datei zu lesen: Welche Regeln zu meinem Stil und zu Quellen habe ich dir zu Beginn der Sitzung genannt? Antworte in einem Satz.",
  });
  const mB = measurementsOf(executedB);

  const compactions = executedA.run.session?.compactions ?? [];
  const summary = summaryRequests(executedA.run.requests);
  const summaryUsage = summary[0]?.response?.usage ?? null;
  const summaryText = summary[0]?.response?.text ?? null;
  // Semantische Prüfung, sprachneutral: pis Summary-Prompt ist englisch und
  // sprachneutral; Gemma fasst die deutsche Sitzung auf Englisch zusammen
  // (Beobachtung fürs Labbook). Inhalt zählt, nicht die Sprache.
  const preferenceInSummary = Boolean(
    summaryText &&
      /kurze Sätze|short sentences/i.test(summaryText) &&
      /Quelle|cit(?:e|ing) (?:the )?source|source citations|sources for/i.test(summaryText),
  );

  const answerB = mB.answerText ?? "";
  const recallOk =
    /kurz\w* Sätze|short sentences/i.test(answerB) &&
    /Quell\w*|sources|citing/i.test(answerB);

  const answerA = mA.answerText ?? "";

  const requirements = [
    requirement(
      "run-complete",
      "Beide Läufe enden fehlerfrei (Exit 0, kein Timeout)",
      mA.exitCode === 0 && !mA.timedOut && mB.exitCode === 0 && !mB.timedOut ? "pass" : "fail",
      { a: { exitCode: mA.exitCode, timedOut: mA.timedOut }, b: { exitCode: mB.exitCode, timedOut: mB.timedOut } },
    ),
    requirement(
      "compaction-ausgeloest",
      "Die Standard-Compaction löst aus (compaction-Entry in der Session)",
      compactions.length > 0 ? "pass" : "fail",
      { compactions: compactions.length, details: compactions[0]?.details ?? null },
    ),
    requirement(
      "summary-request",
      "Wie im Mock (Experiment 04) entsteht mindestens ein LLM-Summary-Request — hier unter angepasstem Fenster (16384 statt 1000, siehe TINY); mit dem echten Modell kann pi mehrfach compactieren",
      summary.length >= 1 ? "pass" : "fail",
      {
        summaryRequests: summary.length,
        summaryDurationMsTotal: summary.reduce((sum, request) => sum + (request.durationMs ?? 0), 0),
        summaryUsage: summary.map((request) => request.response?.usage ?? null),
      },
    ),
    requirement(
      "praefrenz-in-summary",
      "Die Präferenz überlebt semantisch in der Compaction-Summary (Sprache egal)",
      preferenceInSummary ? "pass" : "fail",
      { summaryText },
    ),
    requirement(
      "final-antwort",
      "Nach der Compaction entsteht in Lauf A eine finale Antwort (kein Output-Budget-Kollaps)",
      answerA.trim().length > 0 ? "pass" : "fail",
      { answerA, lengthClampedRequests: mA.lengthClampedRequests },
    ),
    requirement(
      "praefrenz-nach-resume",
      "Nach --continue erinnert sich das Modell an die Präferenz (semantisch)",
      recallOk ? "pass" : "fail",
      { answerB, summaryRequestsInContinue: summaryRequests(executedB.run.requests).length },
    ),
  ];

  return {
    id: "task-6-compaction",
    title: "Compaction-Experiment: deutsche Präferenz über die Standard-Compaction",
    hypothesis:
      "Die LLM-Summary der Standard-Compaction erhält die deutsche Stil- und Quellen-Präferenz — das ist die Vergleichsbasis gegen pi-vcc, dessen algorithmische Extraktion sie nach Experiment 04 verliert.",
    measurements: {
      a: mA,
      b: mB,
      summary: {
        count: summary.length,
        durationMsTotal: summary.reduce((sum, request) => sum + (request.durationMs ?? 0), 0),
        firstUsage: summaryUsage,
        text: summaryText,
        language: detectLanguage(summaryText),
      },
      summaryRequestsInContinue: summaryRequests(executedB.run.requests).length,
    },
    requirements,
    verdict: smokeVerdict(requirements),
  };
}

// ---------------------------------------------------------------- Orchestrierung

const args = parseArgs(process.argv.slice(2));
const ROOT = args.root ?? runRoot(timestamp());

async function main() {
  const llama = await resolveLlama();
  const provider = {
    upstreamBaseUrl: llama.baseUrl,
    apiKey: llama.apiKey,
    name: "pi-local",
    model: "local-model",
    // Produktiv-Default der komki-Instanz: pi nimmt 16384, wenn models.json
    // kein maxTokens setzt (provider-composer.js). Der Vorlauf mit 4096
    // schnitt Aufgabe 2 beim großen quellen.json-Write ab — siehe Labbook.
    maxTokens: 16384,
  };

  console.log(`llama-server: port ${llama.port}, pid ${llama.pid}, auth=${llama.authRequired}`);
  console.log(`gguf: ${llama.gguf}`);
  console.log(`run root:   ${ROOT}`);

  const tasks = [
    ["1", () => task1Top(llama, provider)],
    ["2", () => task2Quellen(llama, provider)],
    ["3", () => task3Redigieren(llama, provider)],
    ["4", () => task4Todo(llama, provider)],
    ["6", () => task6Compaction(llama, provider)],
  ];

  const results = [];
  for (const [key, task] of tasks) {
    if (!selectTask(args.only, key)) continue;
    console.log(`\n=== Aufgabe ${key} ===`);
    try {
      const result = await task();
      results.push(result);
      console.log(`Verdict: ${result.verdict.toUpperCase()}`);
      for (const req of result.requirements) {
        console.log(`  ${req.status.toUpperCase().padEnd(10)} ${req.id}`);
      }
    } catch (error) {
      const failed = {
        id: `task-${key}`,
        title: `Aufgabe ${key}`,
        verdict: "fail",
        harnessError: String(error?.stack ?? error),
      };
      results.push(failed);
      console.log(`HARNESS ERROR: ${failed.harnessError}`);
    }
  }

  const outDir = path.join(ROOT, "results");
  await mkdir(outDir, { recursive: true });
  for (const result of results) {
    await writeFile(
      path.join(outDir, `${result.id}.json`),
      JSON.stringify(result, null, 2),
    );
  }

  const summary = {
    at: new Date().toISOString(),
    root: ROOT,
    llama: {
      port: llama.port,
      pid: llama.pid,
      authRequired: llama.authRequired,
      gguf: llama.gguf,
      ctx: llama.ctx,
      rssMiB: llamaRssMiB(llama.pid),
    },
    results: results.map((result) => ({
      id: result.id,
      title: result.title,
      verdict: result.verdict,
      requirements: result.requirements?.map((req) => ({ id: req.id, status: req.status })),
    })),
  };
  await writeFile(path.join(ROOT, "results.json"), JSON.stringify(summary, null, 2));

  const lines = ["# Realmodell-Smoke-Test — Ergebnisentwurf", ""];
  lines.push(`- Lauf: ${summary.at}`);
  lines.push(`- Root: ${ROOT}`);
  lines.push(
    `- llama-server: port ${llama.port}, pid ${llama.pid}, auth=${llama.authRequired}, RSS ${summary.llama.rssMiB} MiB`,
  );
  lines.push("");
  lines.push("| Aufgabe | Verdikt | Dauer | Requests | Tokens (Prompt/Completion) | Tool-Calls (Fehler) |");
  lines.push("|---|---|---|---|---|---|");
  for (const result of results) {
    const verdict = result.verdict ?? "harness-error";
    const all = Object.values(result.measurements ?? {}).filter(
      (x) => x && typeof x === "object" && x.durationMs !== undefined,
    );
    const measures = result.measurements?.durationMs !== undefined
      ? [result.measurements]
      : all;
    if (measures.length === 0) {
      lines.push(`| ${result.id} | ${verdict} | – | – | – | – |`);
      continue;
    }
    const duration = measures.reduce((sum, x) => sum + (x.durationMs ?? 0), 0);
    const requests = measures.reduce((sum, x) => sum + (x.proxyRequests?.length ?? 0), 0);
    const prompt = measures.reduce((sum, x) => sum + (x.usageProxy?.prompt ?? 0), 0);
    const completion = measures.reduce((sum, x) => sum + (x.usageProxy?.completion ?? 0), 0);
    const calls = measures.reduce((sum, x) => sum + (x.toolCalls?.length ?? 0), 0);
    const errors = measures.reduce((sum, x) => sum + (x.toolCallErrorCount ?? 0), 0);
    lines.push(
      `| ${result.id} | ${verdict} | ${Math.round(duration / 100) / 10}s | ${requests} | ${prompt}/${completion} | ${calls} (${errors}) |`,
    );
  }
  await writeFile(path.join(ROOT, "SMOKE.md"), lines.join("\n") + "\n");

  console.log(`\nErgebnisse: ${path.join(ROOT, "results.json")}`);
  console.log(`Entwurf:    ${path.join(ROOT, "SMOKE.md")}`);

  const blocking = results.filter(
    (result) => result.verdict === "fail" || result.harnessError,
  );
  process.exitCode = blocking.length > 0 ? 1 : 0;
}

try {
  await main();
} catch (error) {
  console.error(String(error?.message ?? error));
  process.exitCode = 2;
}
