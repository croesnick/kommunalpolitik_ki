#!/usr/bin/env node
/**
 * Blind grading and evaluation of the model A/B (Ticket #285).
 *
 *   node smoke/grade-ab.mjs blind  --root <ab-root>
 *     Copies the outputs of tasks 1–3 of all measured runs under neutral
 *     random IDs to <root>/blind/task-N/<id>.txt (shuffled per task),
 *     computes the automatic checklist points (auto.json, without arm
 *     labels) and writes the template for manual grading (grades.json).
 *     The key is kept separately in <root>/blind-key.json and is read only
 *     by `report`.
 *
 *   node smoke/grade-ab.mjs report --root <ab-root>
 *     Unblinds, joins automatic and manual points, computes medians and
 *     ranges per arm, checks the pre-registered gates and writes
 *     <root>/report.json and <root>/REPORT.md.
 *
 * The checklists below are pre-registered (labbook #285, section
 * "Pre-Registration"): they must not change after the measured runs.
 */
import { randomBytes } from "node:crypto";
import { existsSync } from "node:fs";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import path from "node:path";

import { parseSessionFile } from "../lib/session.mjs";
import { checkAnswer } from "./criteria.mjs";
import { ENTWURF_BESCHLUSSVORLAGE, factTokens, missingFacts } from "./fixtures.mjs";

// ---------------------------------------------------------------- checklists

/** Manual items per task (graded blind, 1 point each; true/false). */
export const MANUAL = {
  1: [
    { id: "M1", text: "Höchstens fünf Sätze (Vorgabe des Prompts)." },
    { id: "M2", text: "Keine sachliche Verfälschung: Rollen (Ausschuss empfiehlt dem Rat), Beträge, Auflagen und offene Punkte korrekt zugeordnet." },
    { id: "M3", text: "Deutsch, flüssig, ohne Sprachmischung, ohne Denk- oder Tool-Syntax im Text." },
  ],
  3: [
    { id: "F0", fact: true, text: "Nichts hinzuerfunden (keine neue Tatsachenbehauptung, Zahl, Frist oder Bedingung)." },
    { id: "F1", fact: true, text: "Abschnitt Bahnhofplatz bis Rathausplatz." },
    { id: "F2", fact: true, text: "Baubeginn 03.02.2027 (jede Datumsform)." },
    { id: "F3", fact: true, text: "Bauzeit zwölf Wochen (Wort oder Ziffer)." },
    { id: "F4", fact: true, text: "Bereich Bahnhofstraße Hausnummern 4 bis 12." },
    { id: "F5", fact: true, text: "Gehwege von 2,5 m auf 4,0 m verbreitert." },
    { id: "F6", fact: true, text: "21 Straßenbäume neu gepflanzt." },
    { id: "F7", fact: true, text: "Gesamtkosten 240.000 Euro (veranschlagt)." },
    { id: "F8", fact: true, text: "Eigenanteil 80.000 Euro trägt die Stadt." },
    { id: "F9", fact: true, text: "Rest über Förderung nach der Förderrichtlinie des Landes vom 19.09.2026." },
    { id: "F10", fact: true, text: "Bitte um Zustimmung des Rats zu Maßnahme und Kostenschätzung im Vorgriff auf die Haushaltsplanung 2027." },
    { id: "S2", text: "Klare Sätze, überwiegend aktive Form." },
    { id: "S3", text: "Doppelungen und Tippfehler des Entwurfs beseitigt (möchte möchte, dieFortentwicklung, Doppelformeln)." },
    { id: "S4", text: "Modalität der Förderung erhalten (Rest „kann“ gedeckt werden, nicht als sicher dargestellt)." },
    { id: "S5", text: "Textsorte erhalten: deutsche Beschlussvorlage an den Rat mit Beschlussbitte." },
  ],
};

const DATE_FORMS = [
  /^(\d{1,2})\.(\d{1,2})\.(\d{4})$/,
  /^(\d{4})-(\d{2})-(\d{2})$/,
];

function normDate(value) {
  if (value === null || value === undefined || value === "") return null;
  const text = String(value).trim();
  const dmy = DATE_FORMS[0].exec(text);
  if (dmy) return `${Number(dmy[1])}.${Number(dmy[2])}.${dmy[3]}`;
  const iso = DATE_FORMS[1].exec(text);
  if (iso) return `${Number(iso[3])}.${Number(iso[2])}.${iso[1]}`;
  const tokens = [...factTokens(text)].filter((t) => t.startsWith("date:"));
  return tokens.length === 1 ? tokens[0].slice(5) : text;
}

function pages(value) {
  if (value === null || value === undefined || value === "") return [];
  return (String(value).match(/\d+/g) ?? []).map(Number);
}

const quelleText = (entry) => `${entry?.Quelle ?? ""}`;
const isVep = (entry) => /Verkehrsentwicklungsplan|VEP/i.test(quelleText(entry));

/** Expected sources of the status report (task 2) with accepted field values. */
export const QUELLEN_SOLL = [
  { id: "VEP S. 14", match: (e) => /2026-V-118/.test(quelleText(e)) || (isVep(e) && pages(e.Seite).includes(14)), abruf: ["2.10.2026"], seite: [14] },
  { id: "VEP S. 22", match: (e) => isVep(e) && pages(e.Seite).includes(22), abruf: [null, "2.10.2026"], seite: [22] },
  { id: "Gutachten Soz-017", match: (e) => /Soz-017|Barrierefreiheit/i.test(quelleText(e)), abruf: [null], seite: [7, 9] },
  { id: "StVO § 45", match: (e) => /stvo|§\s*45/i.test(quelleText(e)), abruf: ["5.10.2026"], seite: [] },
  { id: "Förderrichtlinie", match: (e) => /strassenbau-2026|Förderrichtlinie/i.test(quelleText(e)), abruf: ["5.10.2026"], seite: [6] },
  { id: "Amtsblatt/Haushalt", match: (e) => /Amtsblatt|Haushaltsplan/i.test(quelleText(e)), abruf: ["9.10.2026"], seite: [31] },
];
const ABRUF_IM_TEXT = new Set(["2.10.2026", "5.10.2026", "9.10.2026"]);
const SEITEN_IM_TEXT = new Set([14, 22, 7, 8, 9, 6, 31]);

function seiteOk(expected, value) {
  const got = pages(value);
  if (expected.length === 0) return got.length === 0;
  if (expected.length === 2 && expected[0] === 7) {
    // page range 7–9: both bounds present, nothing outside
    return got.includes(7) && got.includes(9) && got.every((p) => p >= 7 && p <= 9);
  }
  return got.length === expected.length && expected.every((p) => got.includes(p));
}

function autoTask1(answer) {
  const { erfuellt, zahlen } = checkAnswer(answer ?? "");
  const k6streng = /80[.\s ]?000|80 Tausend/.test(answer ?? "");
  const items = { ...erfuellt, K6: k6streng };
  return { items, details: { erfundeneZahlen: zahlen.erfunden, abgeleiteteZahlen: zahlen.abgeleitet } };
}

export function autoTask2(raw) {
  let entries = null;
  try {
    const parsed = JSON.parse(raw ?? "");
    if (Array.isArray(parsed)) entries = parsed.filter((e) => e && typeof e === "object");
  } catch {}
  const items = {
    Q0: entries !== null && entries.length > 0 && entries.every((e) => "Quelle" in e && "Abrufdatum" in e && "Seite" in e),
  };
  const perSource = {};
  for (const soll of QUELLEN_SOLL) {
    let best = { present: false, abruf: false, seite: false };
    for (const entry of (entries ?? []).filter(soll.match)) {
      const candidate = {
        present: true,
        abruf: soll.abruf.includes(normDate(entry.Abrufdatum)),
        seite: seiteOk(soll.seite, entry.Seite),
      };
      const score = (c) => Number(c.present) + Number(c.abruf) + Number(c.seite);
      if (score(candidate) > score(best)) best = candidate;
    }
    perSource[soll.id] = best;
    items[`${soll.id}: vorhanden`] = best.present;
    items[`${soll.id}: Abrufdatum`] = best.abruf;
    items[`${soll.id}: Seite`] = best.seite;
  }
  items["Q9: keine erfundenen Abrufdaten/Seiten"] =
    entries !== null &&
    entries.every(
      (e) =>
        (normDate(e.Abrufdatum) === null || ABRUF_IM_TEXT.has(normDate(e.Abrufdatum))) &&
        pages(e.Seite).every((p) => SEITEN_IM_TEXT.has(p)),
    );
  return { items, details: { entryCount: entries?.length ?? 0, perSource } };
}

function autoTask3(edited) {
  if (edited === null) {
    return { items: { S1: false }, vorpruefung: { fehlt: true } };
  }
  const originalWords = ENTWURF_BESCHLUSSVORLAGE.split(/\s+/).length;
  const editedWords = edited.split(/\s+/).length;
  const missing = missingFacts(ENTWURF_BESCHLUSSVORLAGE, edited);
  const original = factTokens(ENTWURF_BESCHLUSSVORLAGE);
  const added = [...factTokens(edited)].filter((token) => !original.has(token));
  return {
    // The pre-check does not count towards the score (F0–F10 cover the
    // facts); it shows the blind grader missing and new numbers.
    items: { S1: editedWords <= Math.round(originalWords * 0.8) },
    vorpruefung: { missingFacts: missing, hinzugekommeneZahlen: added, originalWords, editedWords },
  };
}

// ---------------------------------------------------------------- blind

async function readMaybe(file) {
  try {
    return await readFile(file, "utf8");
  } catch {
    return null;
  }
}

async function measuredRuns(root) {
  const schedule = JSON.parse(await readFile(path.join(root, "schedule.json"), "utf8"));
  return schedule.filter((entry) => entry.kind === "measured" && existsSync(path.join(root, entry.dir, "results.json")));
}

async function artifactOf(root, entry, task) {
  const dir = path.join(root, entry.dir);
  if (task === 1) {
    const result = JSON.parse((await readMaybe(path.join(dir, "results", "task-1-top.json"))) ?? "null");
    return result?.measurements?.answerText ?? null;
  }
  if (task === 2) return readMaybe(path.join(dir, "task-2-quellen", "work", "quellen.json"));
  return readMaybe(path.join(dir, "task-3-redigieren", "work", "neue-fassung.md"));
}

function shuffle(list) {
  const out = [...list];
  for (let i = out.length - 1; i > 0; i -= 1) {
    const j = randomBytes(4).readUInt32BE(0) % (i + 1);
    [out[i], out[j]] = [out[j], out[i]];
  }
  return out;
}

async function blind(root) {
  const blindDir = path.join(root, "blind");
  if (existsSync(path.join(root, "blind-key.json"))) {
    throw new Error("blind-key.json existiert schon — Verblindung nicht wiederholen");
  }
  const runs = await measuredRuns(root);
  const key = {};
  const auto = {};
  const grades = {};
  for (const task of [1, 2, 3]) {
    await mkdir(path.join(blindDir, `task-${task}`), { recursive: true });
    for (const entry of shuffle(runs)) {
      const id = `t${task}-${randomBytes(3).toString("hex")}`;
      const artifact = await artifactOf(root, entry, task);
      key[id] = { task, arm: entry.arm, round: entry.round, dir: entry.dir };
      await writeFile(path.join(blindDir, `task-${task}`, `${id}.txt`), artifact ?? "(kein Output: Datei fehlt)\n");
      auto[id] =
        task === 1 ? autoTask1(artifact) : task === 2 ? autoTask2(artifact) : autoTask3(artifact);
      if (MANUAL[task]) {
        grades[id] = Object.fromEntries(MANUAL[task].map((item) => [item.id, null]));
        grades[id].notiz = "";
      }
    }
  }
  await writeFile(path.join(root, "blind-key.json"), JSON.stringify(key, null, 2), { mode: 0o600 });
  await writeFile(path.join(blindDir, "auto.json"), JSON.stringify(auto, null, 2));
  await writeFile(path.join(blindDir, "grades.json"), JSON.stringify(grades, null, 2));
  await writeFile(path.join(blindDir, "checklisten.json"), JSON.stringify(MANUAL, null, 2));
  console.log(`${Object.keys(key).length} Outputs verblindet: ${blindDir}`);
}

// ---------------------------------------------------------------- report

function median(values) {
  const list = values.filter((v) => typeof v === "number" && Number.isFinite(v)).sort((a, b) => a - b);
  if (list.length === 0) return null;
  const mid = Math.floor(list.length / 2);
  return list.length % 2 ? list[mid] : (list[mid - 1] + list[mid]) / 2;
}

function spread(values) {
  const list = values.filter((v) => typeof v === "number" && Number.isFinite(v));
  if (list.length === 0) return { median: null, min: null, max: null, n: 0, values: [] };
  return { median: median(list), min: Math.min(...list), max: Math.max(...list), n: list.length, values: list };
}

/** All single measurements of a task (tasks 4 and 6 have a and b). */
function measuresOf(result) {
  const m = result?.measurements;
  if (!m) return [];
  if (m.durationMs !== undefined) return [m];
  return [m.a, m.b].filter(Boolean);
}

/**
 * Distinct tool results with isError of a task. The session after
 * --continue (tasks 4, 6) repeats the results of the first run, hence the
 * union over toolCallId. pi turns a schema-invalid call into an isError
 * result as well, so it counts exactly once.
 */
async function errorResults(measures) {
  const byId = new Map();
  for (const m of measures) {
    if (!m.sessionFile) continue;
    const session = await parseSessionFile(m.sessionFile).catch(() => null);
    for (const result of session?.toolResults ?? []) byId.set(result.toolCallId, result);
  }
  return [...byId.values()].filter((r) => r.isError);
}

async function runMetrics(results, summary) {
  const tasks = {};
  const all = [];
  for (const result of results) {
    const measures = measuresOf(result);
    all.push(...measures);
    const requests = measures.flatMap((m) => m.proxyRequests ?? []);
    tasks[result.id] = {
      verdict: result.verdict ?? "harness-error",
      wallMs: measures.reduce((s, m) => s + (m.durationMs ?? 0), 0),
      timedOut: measures.some((m) => m.timedOut),
      ttftFirstMs: requests[0]?.firstTokenMs ?? null,
      firstAnswerFirstMs: requests[0]?.firstAnswerMs ?? null,
      completionTokens: measures.reduce((s, m) => s + (m.usageProxy?.completion ?? 0), 0),
      reasoningTokens: measures.reduce((s, m) => s + (m.reasoningTokens ?? 0), 0),
      requests: requests.length,
    };
  }
  const requests = all.flatMap((m) => m.proxyRequests ?? []);
  const server = all.flatMap((m) => m.serverRequests ?? []);
  const toolCalls = all.flatMap((m) => m.toolCalls ?? []);
  const toolErrors = [];
  for (const result of results) toolErrors.push(...(await errorResults(measuresOf(result))));
  const finishReasons = {};
  for (const request of requests) {
    const reason = request.finishReason ?? "none";
    finishReasons[reason] = (finishReasons[reason] ?? 0) + 1;
  }
  const evalTokens = server.reduce((s, r) => s + (r.evalTokens ?? 0), 0);
  const evalMs = server.reduce((s, r) => s + (r.evalMs ?? 0), 0);
  const promptTokens = server.reduce((s, r) => s + (r.promptTokens ?? 0), 0);
  const promptMs = server.reduce((s, r) => s + (r.promptMs ?? 0), 0);
  const task6 = results.find((r) => r.id === "task-6-compaction");
  const req = (r, id) => r?.requirements?.find((x) => x.id === id)?.status ?? null;
  return {
    tasks,
    loadMs: summary.llama?.staging?.loadMs ?? null,
    wallMsTotal: Object.values(tasks).reduce((s, t) => s + t.wallMs, 0),
    decodeTps: evalMs ? (evalTokens / evalMs) * 1000 : null,
    prefillTps: promptMs ? (promptTokens / promptMs) * 1000 : null,
    ttftMedianMs: median(requests.map((r) => r.firstTokenMs)),
    firstAnswerMedianMs: median(requests.map((r) => r.firstAnswerMs)),
    promptTokens: all.reduce((s, m) => s + (m.usageProxy?.prompt ?? 0), 0),
    completionTokens: all.reduce((s, m) => s + (m.usageProxy?.completion ?? 0), 0),
    reasoningTokens: all.reduce((s, m) => s + (m.reasoningTokens ?? 0), 0),
    toolCalls: toolCalls.length,
    toolCallsInvalid: toolCalls.filter((c) => !c.valid).length,
    toolCallClasses: toolCalls.reduce((acc, c) => ({ ...acc, [c.class]: (acc[c.class] ?? 0) + 1 }), {}),
    toolResultsError: toolErrors.length,
    lengthClamped: all.reduce((s, m) => s + (m.lengthClampedRequests?.length ?? 0), 0),
    finishReasons,
    footprintMaxMiB: Math.max(0, ...all.map((m) => m.footprintLlamaMiB ?? 0)) || null,
    rssMaxMiB: Math.max(0, ...all.map((m) => m.rssLlamaMiB?.after ?? 0)) || null,
    compaction: task6
      ? {
          compactions: task6.requirements?.find((x) => x.id === "compaction-ausgeloest")?.evidence?.compactions ?? null,
          summaryRequests: task6.measurements?.summary?.count ?? null,
          summaryMs: task6.measurements?.summary?.durationMsTotal ?? null,
          summaryLanguage: task6.measurements?.summary?.language ?? null,
          praeferenzInSummary: req(task6, "praefrenz-in-summary"),
          praeferenzNachResume: req(task6, "praefrenz-nach-resume"),
          finalAntwort: req(task6, "final-antwort"),
        }
      : null,
  };
}

function scoreOf(task, autoEntry, manualEntry) {
  const autoItems = Object.values(autoEntry?.items ?? {});
  const manualItems = Object.values(manualEntry ?? {}).filter((v) => typeof v === "boolean");
  const points = [...autoItems, ...manualItems].filter(Boolean).length;
  const max = autoItems.length + (MANUAL[task]?.length ?? 0);
  return { points, max };
}

const fmt = (value, digits = 0) =>
  value === null || value === undefined ? "–" : Number(value).toLocaleString("de-DE", { maximumFractionDigits: digits, minimumFractionDigits: digits });
const fmtSpread = (s, digits = 0, unit = "") =>
  s.n === 0 ? "–" : `${fmt(s.median, digits)}${unit} (${fmt(s.min, digits)}–${fmt(s.max, digits)})`;

async function report(root) {
  const key = JSON.parse(await readFile(path.join(root, "blind-key.json"), "utf8"));
  const auto = JSON.parse(await readFile(path.join(root, "blind", "auto.json"), "utf8"));
  const grades = JSON.parse(await readFile(path.join(root, "blind", "grades.json"), "utf8"));
  const open = Object.entries(grades).filter(([, g]) => Object.entries(g).some(([k, v]) => k !== "notiz" && typeof v !== "boolean"));
  if (open.length > 0) throw new Error(`${open.length} Outputs noch nicht vollständig bewertet (grades.json)`);

  const runs = await measuredRuns(root);
  const arms = [...new Set(runs.map((r) => r.arm))].sort();
  const perRun = [];
  for (const entry of runs) {
    const dir = path.join(root, entry.dir);
    const summary = JSON.parse(await readFile(path.join(dir, "results.json"), "utf8"));
    const results = [];
    for (const r of summary.results) {
      results.push(JSON.parse(await readFile(path.join(dir, "results", `${r.id}.json`), "utf8")));
    }
    perRun.push({ ...entry, metrics: await runMetrics(results, summary) });
  }

  const quality = {};
  for (const [id, info] of Object.entries(key)) {
    const score = scoreOf(info.task, auto[id], grades[id]);
    const factViolations =
      info.task === 3 ? MANUAL[3].filter((item) => item.fact && grades[id][item.id] === false).map((item) => item.id) : [];
    quality[id] = { ...info, ...score, factViolations, notiz: grades[id]?.notiz ?? "" };
  }

  const byArm = {};
  for (const arm of arms) {
    const armRuns = perRun.filter((r) => r.arm === arm);
    const pick = (fn) => spread(armRuns.map((r) => fn(r.metrics)));
    const q = Object.values(quality).filter((x) => x.arm === arm);
    const calls = armRuns.reduce((s, r) => s + r.metrics.toolCalls, 0);
    const repairs = armRuns.reduce((s, r) => s + r.metrics.toolResultsError, 0);
    byArm[arm] = {
      runs: armRuns.map((r) => ({ dir: r.dir, seed: r.seed, round: r.round })),
      loadMs: pick((m) => m.loadMs),
      wallMsTotal: pick((m) => m.wallMsTotal),
      decodeTps: pick((m) => m.decodeTps),
      prefillTps: pick((m) => m.prefillTps),
      ttftMedianMs: pick((m) => m.ttftMedianMs),
      firstAnswerMedianMs: pick((m) => m.firstAnswerMedianMs),
      promptTokens: pick((m) => m.promptTokens),
      completionTokens: pick((m) => m.completionTokens),
      reasoningTokens: pick((m) => m.reasoningTokens),
      footprintMaxMiB: pick((m) => m.footprintMaxMiB),
      lengthClamped: pick((m) => m.lengthClamped),
      taskWallMs: Object.fromEntries(
        Object.keys(armRuns[0]?.metrics.tasks ?? {}).map((t) => [t, pick((m) => m.tasks[t]?.wallMs)]),
      ),
      taskTtftFirstMs: Object.fromEntries(
        Object.keys(armRuns[0]?.metrics.tasks ?? {}).map((t) => [t, pick((m) => m.tasks[t]?.ttftFirstMs)]),
      ),
      verdicts: Object.fromEntries(
        Object.keys(armRuns[0]?.metrics.tasks ?? {}).map((t) => [t, armRuns.map((r) => r.metrics.tasks[t]?.verdict)]),
      ),
      toolCalls: calls,
      repairs,
      repairRate: calls ? repairs / calls : null,
      toolCallClasses: armRuns.reduce((acc, r) => {
        for (const [k, v] of Object.entries(r.metrics.toolCallClasses)) acc[k] = (acc[k] ?? 0) + v;
        return acc;
      }, {}),
      finishReasons: armRuns.reduce((acc, r) => {
        for (const [k, v] of Object.entries(r.metrics.finishReasons)) acc[k] = (acc[k] ?? 0) + v;
        return acc;
      }, {}),
      compaction: armRuns.map((r) => r.metrics.compaction),
      quality: Object.fromEntries(
        [1, 2, 3].map((task) => {
          const items = q.filter((x) => x.task === task);
          return [task, { ...spread(items.map((x) => x.points)), maxPoints: items[0]?.max ?? null }];
        }),
      ),
      factViolationsTask3: q.filter((x) => x.task === 3).map((x) => x.factViolations),
    };
  }

  // gates (pre-registered): arm A (the pin) is the reference
  const gates = {};
  for (const arm of arms) {
    const a = byArm[arm];
    const pin = byArm.A;
    const h1 = a.factViolationsTask3.length > 0 && a.factViolationsTask3.every((v) => v.length === 0);
    const h2 = pin && a.repairRate !== null && pin.repairRate !== null ? a.repairRate <= pin.repairRate : null;
    const better = [1, 2, 3].filter((t) => pin && a.quality[t].median !== null && a.quality[t].median >= pin.quality[t].median);
    gates[arm] = {
      H1_faktentreue: h1,
      H2_reparaturrate: h2,
      Q_qualitaet: arm === "A" ? null : better.length >= 2,
      qualitaetGePin: better,
    };
  }

  const out = { root, at: new Date().toISOString(), arms, byArm, gates, perRun, quality };
  await writeFile(path.join(root, "report.json"), JSON.stringify(out, null, 2));
  await writeFile(path.join(root, "REPORT.md"), renderMarkdown(out));
  console.log(`Bericht: ${path.join(root, "REPORT.md")}`);
}

function renderMarkdown({ arms, byArm, gates, perRun, quality }) {
  const lines = ["# Modell-A/B — Auswertung (generiert von grade-ab.mjs)", ""];
  const row = (label, fn) => lines.push(`| ${label} | ${arms.map((arm) => fn(byArm[arm])).join(" | ")} |`);
  lines.push(`| Messgröße (Median, Spanne über n Messläufe) | ${arms.join(" | ")} |`);
  lines.push(`|---|${arms.map(() => "---").join("|")}|`);
  row("Ladezeit", (a) => fmtSpread({ ...a.loadMs, median: a.loadMs.median / 1000, min: a.loadMs.min / 1000, max: a.loadMs.max / 1000 }, 1, " s"));
  row("Wandzeit gesamt", (a) => fmtSpread({ ...a.wallMsTotal, median: a.wallMsTotal.median / 1000, min: a.wallMsTotal.min / 1000, max: a.wallMsTotal.max / 1000 }, 0, " s"));
  row("Decode t/s", (a) => fmtSpread(a.decodeTps, 1));
  row("Prefill t/s", (a) => fmtSpread(a.prefillTps, 0));
  row("TTFT (Median je Request)", (a) => fmtSpread(a.ttftMedianMs, 0, " ms"));
  row("erste Antwort (ohne Thinking)", (a) => fmtSpread(a.firstAnswerMedianMs, 0, " ms"));
  row("Prompt-Token", (a) => fmtSpread(a.promptTokens));
  row("Completion-Token", (a) => fmtSpread(a.completionTokens));
  row("davon Thinking-Token", (a) => fmtSpread(a.reasoningTokens));
  row("footprint max", (a) => fmtSpread(a.footprintMaxMiB, 0, " MiB"));
  row("längengeklemmte Requests", (a) => fmtSpread(a.lengthClamped));
  row("Tool-Calls / invalide / Reparaturen", (a) => `${a.toolCalls} / ${a.toolCallClasses ? Object.entries(a.toolCallClasses).filter(([k]) => k !== "ok" && k !== "extra-keys").reduce((x, [, v]) => x + v, 0) : 0} / ${a.repairs} (${fmt((a.repairRate ?? 0) * 100, 1)} %)`);
  row("finishReasons", (a) => Object.entries(a.finishReasons).map(([k, v]) => `${k} ${v}`).join(", "));
  lines.push("");
  lines.push(`| Aufgabe: Wandzeit | ${arms.join(" | ")} |`);
  lines.push(`|---|${arms.map(() => "---").join("|")}|`);
  for (const task of Object.keys(byArm[arms[0]].taskWallMs)) {
    row(task, (a) => {
      const s = a.taskWallMs[task] ?? { n: 0 };
      return `${s.n ? fmtSpread({ ...s, median: s.median / 1000, min: s.min / 1000, max: s.max / 1000 }, 1, " s") : "–"} · ${(a.verdicts[task] ?? []).join("/")}`;
    });
  }
  lines.push("");
  lines.push(`| Qualität (Punkte, Median, Spanne) | ${arms.join(" | ")} |`);
  lines.push(`|---|${arms.map(() => "---").join("|")}|`);
  for (const task of [1, 2, 3]) row(`Aufgabe ${task}`, (a) => `${fmtSpread(a.quality[task])} / ${a.quality[task].maxPoints}`);
  row("Faktenänderungen Aufgabe 3 je Lauf", (a) => a.factViolationsTask3.map((v) => v.length).join(" / "));
  lines.push("");
  lines.push(`| Gate | ${arms.join(" | ")} |`);
  lines.push(`|---|${arms.map(() => "---").join("|")}|`);
  const yn = (v) => (v === null ? "–" : v ? "bestanden" : "**nicht bestanden**");
  row("H1 0 Faktenänderungen (A3, jeder Lauf)", (a) => yn(gates[Object.keys(byArm).find((k) => byArm[k] === a)].H1_faktentreue));
  row("H2 Reparaturrate ≤ Pin", (a) => yn(gates[Object.keys(byArm).find((k) => byArm[k] === a)].H2_reparaturrate));
  row("Q Qualität ≥ Pin in ≥ 2 von 3", (a) => {
    const g = gates[Object.keys(byArm).find((k) => byArm[k] === a)];
    return `${yn(g.Q_qualitaet)} (${g.qualitaetGePin.join(", ") || "keine"})`;
  });
  lines.push("");
  lines.push("## Läufe");
  lines.push("");
  lines.push("| Lauf | Arm | Runde | Seed | Ladezeit | Wandzeit | Decode t/s |");
  lines.push("|---|---|---|---|---|---|---|");
  for (const run of perRun) {
    lines.push(`| ${run.dir} | ${run.arm} | ${run.round} | ${run.seed} | ${fmt(run.metrics.loadMs / 1000, 1)} s | ${fmt(run.metrics.wallMsTotal / 1000)} s | ${fmt(run.metrics.decodeTps, 1)} |`);
  }
  lines.push("");
  lines.push("## Blindbewertung (entblindet)");
  lines.push("");
  lines.push("| ID | Aufgabe | Arm | Runde | Punkte | Faktenänderungen | Notiz |");
  lines.push("|---|---|---|---|---|---|---|");
  for (const [id, q] of Object.entries(quality).sort((x, y) => x[1].task - y[1].task || x[1].arm.localeCompare(y[1].arm) || x[1].round - y[1].round)) {
    lines.push(`| ${id} | ${q.task} | ${q.arm} | ${q.round} | ${q.points}/${q.max} | ${q.factViolations.join(", ") || "–"} | ${q.notiz.replace(/\|/g, "/")} |`);
  }
  return lines.join("\n") + "\n";
}

// ---------------------------------------------------------------- main

async function main() {
  const [command, ...rest] = process.argv.slice(2);
  const rootIndex = rest.indexOf("--root");
  const root = rootIndex >= 0 ? rest[rootIndex + 1] : null;
  if (!root) throw new Error("--root <ab-root> fehlt");
  if (command === "blind") return blind(root);
  if (command === "report") return report(root);
  throw new Error("Befehl: blind | report");
}

if (import.meta.url === `file://${process.argv[1]}`) {
  try {
    await main();
  } catch (error) {
    console.error(String(error?.message ?? error));
    process.exitCode = 2;
  }
}
