#!/usr/bin/env node
/**
 * Skill-Eval-Runner (Ticket #292): misst einen Skill des Repos gegen das
 * Zielmodell der komki-Instanz (Gemma 4 26B im llama-server, Anbindung über
 * pi wie im Produktivbetrieb) und schreibt skills/<name>/BENCHMARK.md.
 *
 * Messfragen je Fall:
 *   verhalten — bringt der Skill die Antwort näher an das gewünschte Verhalten?
 *               Arme: ohne Skill · vorige Fassung · aktuelle Fassung, Skill als
 *               eingefrorene Kopie per --append-system-prompt (simuliert den
 *               vollständig geladenen Skill, wie im Vorlauf #158).
 *   trigger   — greift die Description des Skills? Echter Skill-Mechanismus
 *               (pi --skill, alle Skills registriert, kein Anhängen): gemessen
 *               wird, ob der Ziel-Skill per read geladen wird.
 *   negativ   — darf die Description NICHT greifen: derselbe Mechanismus,
 *               Ziel-Skill darf nicht geladen werden.
 *
 * Methodik (Lehren aus #158, Stand der Technik siehe docs/agents/skill-evals.md):
 *   - Arme laufen abwechselnd: Lauf 1 aller (Fall, Arm)-Paare, dann Lauf 2 …
 *     Der llama-server ist eine geteilte Live-Instanz; Prefix-Cache, Wärme und
 *     Last driften, also verteilt statt geblockt.
 *   - Jeder Lauf gleicht das Server-Logfenster gegen die eigene Proxy-Zählung
 *     ab (serverRequestCountMismatch) — fremde Clients werden sichtbar.
 *   - Bewerter kommen aus der Suite, deterministisch zuerst; llm-Kriterien
 *     werden erst nach allen pi-Läufen bewertet (eigener Richter-Abschnitt,
 *     damit das Logfenster der Messläufe sauber bleibt).
 *   - Rohzählungen, keine „belegt“-Formeln.
 *
 * Aufruf:
 *   node apps/komki_cli/experiments/pi_packages/skill-evals/run.mjs \
 *     --skill sitzungsvorbereitung [--cases a,b] [--laeufe 5] \
 *     [--baseline <git-ref>] [--notizen <datei>] [--root <verz>] \
 *     [--bericht <datei>] [--trockenlauf]
 */
import { execFileSync } from "node:child_process";
import { cp, mkdir, readFile, readdir, rm, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import http from "node:http";

import { PI_VERSION, runRoot, timestamp } from "../lib/config.mjs";
import { runPi } from "../lib/runner.mjs";
import {
  answerText,
  llamaLogOffset,
  llamaLogSegment,
  resolveLlama,
  usageTotals,
  validateToolCalls,
} from "../smoke/measure.mjs";
import { bewerte, starteRichter } from "./lib/bewerter.mjs";
import { berichtMarkdown } from "./lib/bericht.mjs";
import { ladeSuite } from "./lib/suite.mjs";

const HIER = path.dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = path.resolve(HIER, "..", "..", "..", "..", "..");

const ARM_LABEL = {
  "ohne-skill": "ohne Skill",
  vorige: "vorige Fassung",
  aktuelle: "aktuelle Fassung",
};

// ---------------------------------------------------------------- CLI

function parseArgs(argv) {
  const args = {
    skill: null,
    cases: null,
    laeufe: null,
    baseline: "origin/main",
    root: null,
    bericht: null,
    notizen: null,
    trockenlauf: false,
  };
  for (let i = 0; i < argv.length; i += 1) {
    const a = argv[i];
    if (a === "--skill") args.skill = argv[++i];
    else if (a === "--cases") args.cases = new Set((argv[++i] ?? "").split(",").filter(Boolean));
    else if (a === "--laeufe") args.laeufe = Math.max(1, Number(argv[++i]) || 5);
    else if (a === "--baseline") args.baseline = argv[++i];
    else if (a === "--root") args.root = argv[++i];
    else if (a === "--bericht") args.bericht = argv[++i];
    else if (a === "--notizen") args.notizen = argv[++i];
    else if (a === "--trockenlauf") args.trockenlauf = true;
    else throw new Error(`unbekannte Option: ${a}`);
  }
  if (!args.skill) throw new Error("--skill <name> ist Pflicht (z. B. --skill sitzungsvorbereitung)");
  return args;
}

// ---------------------------------------------------------------- Git- und Pin-Helfer

function git(args, optionen = {}) {
  return execFileSync("git", args, { cwd: REPO_ROOT, encoding: "utf8", maxBuffer: 64 * 1024 * 1024, ...optionen });
}

function gitSha(kurz = true) {
  const sha = git(["rev-parse", "HEAD"]).trim();
  return kurz ? sha.slice(0, 8) : sha;
}

async function sha256Von(text) {
  const { createHash } = await import("node:crypto");
  return createHash("sha256").update(text, "utf8").digest("hex");
}

function zeilenVon(text) {
  return text.trimEnd().split("\n").length;
}

/** Skill-Inhalt aus der Arbeitskopie. */
async function skillArbeitskopie(skillName) {
  const file = path.join(REPO_ROOT, "skills", skillName, "SKILL.md");
  try {
    return await readFile(file, "utf8");
  } catch {
    throw new Error(`Skill-Datei fehlt: ${file}`);
  }
}

/** Skill-Inhalt aus einem Git-Stand; wirft mit klarer Meldung bei unbekanntem Stand. */
function skillAusGit(ref, skillName) {
  const relativ = `skills/${skillName}/SKILL.md`;
  try {
    return git(["show", `${ref}:${relativ}`]);
  } catch {
    throw new Error(`keine Skill-Fassung ${relativ} im Git-Stand "${ref}" gefunden`);
  }
}

/** /props (mit Key) abrufen — Sampling-Defaults für den Modell-Pin. */
function propsAbfragen(port, apiKey) {
  return new Promise((resolve) => {
    const req = http.get(
      {
        hostname: "127.0.0.1",
        port,
        path: "/props",
        headers: { authorization: `Bearer ${apiKey}` },
        timeout: 5000,
      },
      (res) => {
        const chunks = [];
        res.on("data", (chunk) => chunks.push(chunk));
        res.on("end", () => {
          try {
            resolve(JSON.parse(Buffer.concat(chunks).toString("utf8")));
          } catch {
            resolve(null);
          }
        });
      },
    );
    req.on("timeout", () => req.destroy());
    req.on("error", () => resolve(null));
  });
}

/** Versionskern aus einem Homebrew-Cellar-Pfad, z. B. „0.7.0“. */
function versionAusPfad(binPath) {
  const m = /Cellar\/[^/]+\/([^/]+)\//.exec(binPath ?? "");
  return m ? m[1] : "unbekannt";
}

// ---------------------------------------------------------------- Arme einfrieren

/**
 * Friert die Skill-Fassungen für die Arme ein (Lehre aus #158: ein Arm, der
 * auf die Arbeitsdatei zeigt, misst Mischstände, wenn parallel editiert wird).
 * brauchtVorige: nur wenn ein verhalten-Fall den Arm verlangt (ein neuer Skill
 * hat noch keinen Vorgänger im Git).
 * Rückgabe: { arme: { 'ohne-skill'|vorige|aktuelle: pin }, snapshotPfad: {arm: datei} }
 */
async function friereArmeEin(args, root, skillName, brauchtVorige) {
  const arbeitskopie = await skillArbeitskopie(skillName);
  const kopieSha = await sha256Von(arbeitskopie);
  const headInhalt = skillAusGit("HEAD", skillName);
  const gleichtHead = arbeitskopie === headInhalt;

  const arme = {};
  const snapshotPfad = {};
  arme["ohne-skill"] = {
    label: "kein Skill im Kontext (--no-skills, kein Anhang)",
    zeilen: null,
    sha256: null,
    herkunft: "–",
  };
  snapshotPfad["ohne-skill"] = null;

  if (brauchtVorige) {
    const baselineInhalt = skillAusGit(args.baseline, skillName);
    const baselineSha = await sha256Von(baselineInhalt);
    arme.vorige = {
      label: `SKILL.md (${zeilenVon(baselineInhalt)} Zeilen)`,
      zeilen: zeilenVon(baselineInhalt),
      sha256: baselineSha,
      herkunft: `git ${args.baseline}`,
    };
    const vorigeDatei = path.join(root, "arme", "vorige", "SKILL.md");
    await mkdir(path.dirname(vorigeDatei), { recursive: true });
    await writeFile(vorigeDatei, baselineInhalt);
    snapshotPfad.vorige = vorigeDatei;

    if (baselineInhalt === arbeitskopie) {
      console.log(
        `Hinweis: vorige Fassung (${args.baseline}) und aktuelle Fassung sind inhaltlich identisch — ` +
          `der Arm-Vergleich verdoppelt für verhalten-Fälle denselben Stand. Für einen echten ` +
          `A/B-Vergleich --baseline <alter-stand> setzen.`,
      );
    }
  }

  arme.aktuelle = {
    label: `SKILL.md (${zeilenVon(arbeitskopie)} Zeilen)`,
    zeilen: zeilenVon(arbeitskopie),
    sha256: kopieSha,
    herkunft: gleichtHead
      ? `Arbeitskopie = HEAD ${gitSha()}`
      : `Arbeitskopie (weicht von HEAD ${gitSha()} ab)`,
  };
  const aktuelleDatei = path.join(root, "arme", "aktuelle", "SKILL.md");
  await mkdir(path.dirname(aktuelleDatei), { recursive: true });
  await writeFile(aktuelleDatei, arbeitskopie);
  snapshotPfad.aktuelle = aktuelleDatei;

  return { arme, snapshotPfad };
}

/** Alle Skill-Verzeichnisse der Arbeitskopie für den echten Mechanismus einfrieren. */
async function friereAlleSkillsEin(root) {
  const quelle = path.join(REPO_ROOT, "skills");
  const ziel = path.join(root, "skills", "alle");
  await rm(ziel, { recursive: true, force: true });
  await mkdir(path.dirname(ziel), { recursive: true });
  const namen = [];
  for (const entry of await readdir(quelle, { withFileTypes: true })) {
    if (!entry.isDirectory()) continue;
    const skillDir = path.join(quelle, entry.name);
    const skillFile = path.join(skillDir, "SKILL.md");
    try {
      await readFile(skillFile, "utf8");
    } catch {
      continue; // kein SKILL.md → für pi kein Skill
    }
    await cp(skillDir, path.join(ziel, entry.name), { recursive: true });
    namen.push(entry.name);
  }
  return { verzeichnis: ziel, namen };
}

// ---------------------------------------------------------------- Lauf-Ausführung

function median(werte) {
  if (werte.length === 0) return null;
  const sortiert = [...werte].sort((a, b) => a - b);
  const mitte = Math.floor(sortiert.length / 2);
  return sortiert.length % 2 === 1
    ? sortiert[mitte]
    : Math.round((sortiert[mitte - 1] + sortiert[mitte]) / 2);
}

/** System-Prompt-Text des ersten Chat-Requests (für die Einbau-Kontrollen); pi kann den Anhang als eigene System-Nachricht senden. */
function systemPromptVon(run) {
  const request = run.requests.find((r) => (r.url ?? "").includes("/chat/completions"));
  const messages = request?.parsed?.messages ?? [];
  return messages
    .filter((m) => m.role === "system")
    .map((m) => (typeof m.content === "string" ? m.content : JSON.stringify(m.content ?? "")))
    .join("\n");
}

async function kopiereFixtures(fall, suiteDir, workDir) {
  for (const rel of fall.fixtures) {
    const inhalt = await readFile(path.join(suiteDir, "cases", fall.id, rel), "utf8");
    const ziel = path.join(workDir, path.basename(rel));
    await mkdir(path.dirname(ziel), { recursive: true });
    await writeFile(ziel, inhalt);
  }
}

// ---------------------------------------------------------------- Hauptprogramm

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const suite = await ladeSuite(REPO_ROOT, args.skill, args.cases);
  const suiteDir = path.join(REPO_ROOT, "skills", args.skill, "evals");
  const laeufeJeFall = (fall) => args.laeufe ?? fall.laeufe;
  const root = args.root ?? runRoot(`${timestamp()}-skill-evals-${args.skill}`);

  console.log(`Suite: ${args.skill} — ${suite.faelle.length} Fall/Fälle`);
  for (const fall of suite.faelle) {
    console.log(
      `  ${fall.id} (${fall.typ}, ${fall.arme.join(" · ")}, ${laeufeJeFall(fall)} Läufe/Arm,` +
        ` ${fall.bewerter.length} Bewerter)`,
    );
  }
  console.log(`Run-Root: ${root}`);

  await mkdir(path.join(root, "antworten"), { recursive: true });

  // Arme einfrieren (immer: auch trigger/negativ brauchen die aktuelle Kopie).
  const brauchtVorige = suite.faelle.some(
    (fall) => fall.typ === "verhalten" && fall.arme.includes("vorige"),
  );
  const { arme, snapshotPfad } = await friereArmeEin(args, root, args.skill, brauchtVorige);

  // Echter Mechanismus: alle Skills registrieren, wenn trigger/negativ-Fälle laufen.
  let alle = null;
  if (suite.faelle.some((fall) => fall.typ !== "verhalten")) {
    alle = await friereAlleSkillsEin(root);
    console.log(`Echter Mechanismus: ${alle.namen.length} Skills registriert (${alle.namen.join(", ")})`);
  }

  const laufplan = [];
  const laeufeJeArm = laeufeJeFall(suite.faelle[0]);
  for (const fall of suite.faelle) {
    for (const arm of fall.arme) {
      for (let lauf = 1; lauf <= laeufeJeFall(fall); lauf += 1) {
        laufplan.push({ fall, arm, lauf });
      }
    }
  }
  // Abwechselnd: alle (Fall, Arm)-Paare je Laufindex, nicht Arm für Arm.
  laufplan.sort((a, b) => a.lauf - b.lauf);
  const gesamt = laufplan.length;
  const planKontrollen = new Set(); // (fall.id, arm) mit bestandener Einbau-Kontrolle

  if (args.trockenlauf) {
    console.log(`\nTrockenlauf: ${gesamt} Läufe geplant, keine Server- oder Modell-Aufrufe.`);
    console.log("Regexe der Bewerter:");
    for (const fall of suite.faelle) {
      for (const b of fall.bewerter) {
        if (b.typ === "enthaelt" || b.typ === "enthaelt-nicht") {
          for (const option of b.optionen) {
            try {
              new RegExp(option, "i");
            } catch (error) {
              throw new Error(`Fall ${fall.id}, Bewerter ${b.id}: Option "${option}" ist kein Regex: ${error.message}`);
            }
          }
        }
        if (b.typ === "tool-call") {
          try {
            new RegExp(b.parameter, "i");
          } catch (error) {
            throw new Error(`Fall ${fall.id}, Bewerter ${b.id}: parameter "${b.parameter}" ist kein Regex: ${error.message}`);
          }
        }
      }
    }
    console.log("  alle Optionen kompilieren.");
    return;
  }

  const llama = await resolveLlama();
  const komkiConfig = JSON.parse(
    await readFile(path.join(llama.base, "config.json"), "utf8"),
  );
  const props = await propsAbfragen(llama.port, llama.apiKey);
  const params = props?.default_generation_settings?.params ?? null;
  const samplingText = params
    ? `temp ${params.temperature} · top-p ${Math.round((params.top_p ?? 0) * 100) / 100} · ` +
      `top-k ${params.top_k} · min-p ${Math.round((params.min_p ?? 0) * 100) / 100} · ` +
      `repeat-penalty ${params.repeat_penalty} · seed ${params.seed === 4294967295 ? "zufällig" : params.seed}`
    : "nicht abfragbar";
  console.log(`llama-server: port ${llama.port}, pid ${llama.pid}`);
  console.log(`Modell: ${komkiConfig.gguf_path}`);

  const provider = {
    upstreamBaseUrl: llama.baseUrl,
    apiKey: llama.apiKey,
    name: "pi-local",
    model: "local-model",
    maxTokens: 16384,
  };

  const richterVorhanden = suite.faelle.some((fall) =>
    fall.bewerter.some((b) => b.typ === "llm"),
  );
  const richter = richterVorhanden
    ? starteRichter({ baseUrl: llama.baseUrl, apiKey: llama.apiKey, model: "local-model" })
    : null;

  const laufErgebnisse = [];
  let fortlauf = 0;
  for (const eintrag of laufplan) {
    const { fall, arm, lauf } = eintrag;
    fortlauf += 1;
    const laufDir = path.join(root, "laeufe", `${fall.id}__${arm}__${lauf}`);
    await rm(laufDir, { recursive: true, force: true });
    const workDir = path.join(laufDir, "work");
    await kopiereFixtures(fall, suiteDir, workDir);

    const extraArgs = [];
    if (fall.typ === "verhalten") {
      if (arm !== "ohne-skill") {
        extraArgs.push("--append-system-prompt", snapshotPfad[arm]);
      }
    } else {
      for (const name of alle.namen) {
        extraArgs.push("--skill", path.join(alle.verzeichnis, name));
      }
    }

    const logStart = await llamaLogOffset(llama);
    const run = await runPi({
      id: `${fall.id}__${arm}__${lauf}`,
      runRoot: root,
      runDir: laufDir,
      provider,
      contextWindow: 131072,
      timeoutMs: fall.timeoutS * 1000,
      tools: fall.tools,
      extraArgs,
      prompt: fall.prompt,
    });
    const logEnd = await llamaLogOffset(llama);
    const serverRequests = await llamaLogSegment(llama, logStart, logEnd);
    const fremdlast =
      serverRequests.length !==
      run.requests.filter((r) => (r.url ?? "").includes("/chat/completions")).length;

    // Einbau-Kontrolle nach dem ersten Lauf je (Fall, Arm): ein still
    // fehlgeschlagenes --append-system-prompt (Pfad existiert nicht → pi hängt
    // den Pfadtext als Literal an) oder eine fehlgeschlagene Skill-Registrierung
    // würde sonst 5 Läufe lang sauber wirkende Messwerte produzieren.
    const kontrollSchluessel = `${fall.id}__${arm}`;
    if (!planKontrollen.has(kontrollSchluessel)) {
      const system = systemPromptVon(run);
      if (fall.typ === "verhalten") {
        const marker = `name: ${args.skill}`;
        const erwartet = arm !== "ohne-skill";
        if (system.includes(marker) !== erwartet) {
          throw new Error(
            `Einbau-Kontrolle fehlgeschlagen für ${fall.id}/${arm}: Skill-Anhang ` +
              `(${marker}) ist ${erwartet ? "nicht" : "unerwartet"} im System-Prompt. ` +
              `Snapshot-Pfad prüfen: ${snapshotPfad[arm]}`,
          );
        }
      } else {
        if (!system.includes("<available_skills>") || !system.includes(args.skill)) {
          throw new Error(
            `Registrierungs-Kontrolle fehlgeschlagen für ${fall.id}/${arm}: ` +
              `<available_skills> ohne ${args.skill} im ersten Request — ` +
              `Skill-Snapshots unter ${alle?.verzeichnis} prüfen.`,
          );
        }
      }
      planKontrollen.add(kontrollSchluessel);
    }

    const toolCalls = validateToolCalls(run.requests);
    const usage = usageTotals(run.requests);
    const antwort = answerText(run.session) ?? "";

    // Deterministische Bewerter sofort; llm-Bewerter erst im Richter-Abschnitt.
    const jeKriterium = {};
    const quelle = (
      await Promise.all(
        fall.fixtures.map((rel) => readFile(path.join(suiteDir, "cases", fall.id, rel), "utf8")),
      )
    ).join("\n\n");
    for (const b of fall.bewerter) {
      if (b.typ === "llm") continue;
      const ergebnis = await bewerte(b, {
        antwort,
        toolCalls,
        dateien: run.files.created,
        quelle,
        richter,
      });
      jeKriterium[b.id] = { bestanden: ergebnis.bestanden, details: ergebnis.details, typ: b.typ };
    }

    const geleseneSkills = {};
    if (fall.typ !== "verhalten") {
      for (const call of toolCalls) {
        const m = /alle[\\/]([A-Za-z0-9_-]+)[\\/]SKILL\.md/i.exec(
          `${call.rawArguments ?? ""} ${JSON.stringify(call.args ?? {})}`,
        );
        if (m) geleseneSkills[m[1]] = true;
      }
    }

    const satz = {
      fall: fall.id,
      typ: fall.typ,
      arm,
      lauf,
      durationMs: run.durationMs,
      timedOut: run.timedOut,
      exitCode: run.code,
      fremdlast,
      promptTokens: usage.prompt,
      completionTokens: usage.completion,
      toolCallFehler: toolCalls.filter((c) => !c.valid).length,
      geleseneSkills: Object.keys(geleseneSkills),
      antwort,
      jeKriterium,
    };
    laufErgebnisse.push(satz);
    await writeFile(
      path.join(root, "antworten", `${fall.id}__${arm}__${lauf}.md`),
      `# ${fall.id} · ${arm} · Lauf ${lauf}\n\n${antwort}\n`,
    );

    const fehlt = Object.entries(jeKriterium)
      .filter(([, e]) => !e.bestanden)
      .map(([id]) => id);
    console.log(
      `[${fortlauf}/${gesamt}] ${fall.id} · ${arm} · Lauf ${lauf}: ` +
        `${Math.round(run.durationMs / 100) / 10} s · ${usage.prompt.toLocaleString("de-DE")} Prompt-Tokens` +
        `${fremdlast ? " · FREMDLAST" : ""}${run.timedOut ? " · TIMEOUT" : ""}` +
        `${run.code !== 0 ? ` · Exit ${run.code}` : ""}` +
        (fehlt.length > 0 ? ` · fehlt: ${fehlt.join(", ")}` : ""),
    );
  }

  // Richter-Abschnitt: llm-Bewerter über kurze Ausgaben, konkrete
  // PASS/FAIL-Bedingungen, dasselbe gepinnte Modell. Erst nach allen
  // Messläufen, damit kein Richter-Request ein Logfenster verfälscht.
  if (richter) {
    console.log(`\nRichter-Abschnitt: llm-Bewerter …`);
    for (const satz of laufErgebnisse) {
      const fall = suite.faelle.find((f) => f.id === satz.fall);
      for (const b of fall.bewerter) {
        if (b.typ !== "llm") continue;
        const ergebnis = await bewerte(b, { antwort: satz.antwort, richter });
        satz.jeKriterium[b.id] = {
          bestanden: ergebnis.bestanden,
          details: ergebnis.details,
          typ: b.typ,
        };
      }
    }
    const richterLaeufe = richter.laeufe;
    console.log(
      `  ${richterLaeufe.length} Richter-Aufrufe, ` +
        `${richterLaeufe.filter((l) => l.usage).reduce((s, l) => s + (l.usage.prompt_tokens ?? 0), 0).toLocaleString("de-DE")} Prompt- / ` +
        `${richterLaeufe.filter((l) => l.usage).reduce((s, l) => s + (l.usage.completion_tokens ?? 0), 0).toLocaleString("de-DE")} Completion-Tokens`,
    );
  }

  // ---------------------------------------------------------------- Zusammenfassen und Bericht

  const faelleFuerBericht = [];
  for (const fall of suite.faelle) {
    const ergebnisse = {};
    const auffaelligkeiten = [];
    for (const arm of fall.arme) {
      const laeufe = laufErgebnisse.filter((e) => e.fall === fall.id && e.arm === arm);
      const jeKriterium = {};
      for (const b of fall.bewerter) {
        jeKriterium[b.id] = {
          bestanden: laeufe.filter((e) => e.jeKriterium[b.id]?.bestanden).length,
          typ: b.typ,
        };
      }
      const geleseneSkills = {};
      if (fall.typ !== "verhalten") {
        for (const satz of laeufe) {
          for (const name of satz.geleseneSkills) {
            geleseneSkills[name] = (geleseneSkills[name] ?? 0) + 1;
          }
        }
      }
      ergebnisse[arm] = {
        laeufeGesamt: laeufe.length,
        timeoutLaeufe: laeufe.filter((e) => e.timedOut).length,
        fehlerLaeufe: laeufe.filter((e) => !e.timedOut && e.exitCode !== 0).length,
        fremdlastLaeufe: laeufe.filter((e) => e.fremdlast).length,
        jeKriterium,
        medianWandzeitMs: median(laeufe.map((e) => e.durationMs)),
        medianPromptTokens: median(laeufe.map((e) => e.promptTokens)),
        medianCompletionTokens: median(laeufe.map((e) => e.completionTokens)),
        toolCallFehler: laeufe.reduce((s, e) => s + e.toolCallFehler, 0),
        geleseneSkills: Object.keys(geleseneSkills).length > 0 ? geleseneSkills : null,
      };

      // Auffälligkeiten: erfundene Zahlen und Links auch dort sichten, wo kein
      // Kriterium sie abfragt (Lehre aus #158: das Lesen der Stichproben fand
      // den Fehler, nicht der Regex).
      for (const b of fall.bewerter) {
        if (b.typ !== "zahlen") continue;
        const tokens = new Map();
        for (const satz of laeufe) {
          const d = satz.jeKriterium[b.id]?.details;
          for (const token of d?.erfunden ?? []) {
            tokens.set(token, (tokens.get(token) ?? 0) + 1);
          }
        }
        if (tokens.size > 0) {
          auffaelligkeiten.push(
            `erfundene Zahlen laut \`${b.id}\` (${ARM_LABEL[arm]}): ` +
              [...tokens.entries()].map(([t, n]) => `${t} (${n} Läufe)`).join(", "),
          );
        }
      }
      const urlLauf = laeufe.filter((e) => /https?:\/\/\S+/.test(e.antwort)).length;
      if (urlLauf > 0) {
        auffaelligkeiten.push(
          `URL in der Antwort (${ARM_LABEL[arm]}): ${urlLauf}/${laeufe.length} Läufe — z. B. ` +
            `\`${(laeufe.find((e) => /https?:\/\/\S+/.test(e.antwort))?.antwort.match(/https?:\/\/\S+/) ?? ["–"])[0]}\``,
        );
      }
      const abrufLauf = laeufe.filter((e) => /abgerufen.{0,24}\d{1,2}\.\d{1,2}\.\d{2,4}/i.test(e.antwort)).length;
      if (abrufLauf > 0) {
        auffaelligkeiten.push(
          `Abrufdatum in der Antwort (${ARM_LABEL[arm]}): ${abrufLauf}/${laeufe.length} Läufe`,
        );
      }
    }
    if (fall.typ === "trigger" || fall.typ === "negativ") {
      const zielGelesen = ergebnisse.aktuelle.geleseneSkills?.[args.skill] ?? 0;
      auffaelligkeiten.push(
        fall.typ === "trigger"
          ? `Ziel-Skill gelesen: ${zielGelesen}/${ergebnisse.aktuelle.laeufeGesamt} Läufe`
          : `Ziel-Skill gelesen: ${zielGelesen}/${ergebnisse.aktuelle.laeufeGesamt} Läufe (erwartet 0)`,
      );
    }
    faelleFuerBericht.push({
      id: fall.id,
      typ: fall.typ,
      beschreibung: fall.beschreibung,
      prompt: fall.prompt,
      quelle: fall.quelle,
      fixtures: fall.fixtures,
      arme: fall.arme,
      laeufe: laeufeJeFall(fall),
      registrierteSkills: alle?.namen.length ?? 0,
      bewerterListe: fall.bewerter.map((b) => ({
        id: b.id,
        typ: b.typ,
        text: b.text,
        quelle: `evals/cases/${fall.id}/${b.quelle}`,
      })),
      ergebnisse,
      auffaelligkeiten,
    });
  }

  const gesamtLaeufe = laufErgebnisse.length;
  const fremdlastLaeufe = laufErgebnisse.filter((e) => e.fremdlast).length;

  let notizen = null;
  if (args.notizen) {
    try {
      notizen = await readFile(args.notizen, "utf8");
    } catch {
      console.warn(`Warnung: --notizen ${args.notizen} nicht lesbar — Bericht ohne Stichproben-Notizen.`);
    }
  }

  const bericht = berichtMarkdown({
    skillName: args.skill,
    datum: new Date().toLocaleDateString("de-DE", { year: "numeric", month: "long", day: "numeric" }),
    rahmen: {
      modell: "Gemma 4 26B-A4B-it (llama.cpp, Zielmodell der komki-Instanz)",
      gguf: path.basename(komkiConfig.gguf_path ?? "unbekannt"),
      ggufSha256: (komkiConfig.gguf_sha256 ?? "unbekannt").slice(0, 16) + "…",
      sampling: samplingText,
      server: `llama.cpp ${versionAusPfad(komkiConfig.llama_server_bin)} · port ${llama.port} · auth erforderlich`,
      pi: `pi ${PI_VERSION}`,
      node: process.version,
      ctx: komkiConfig.ctx ?? 131072,
      maxTokens: 16384,
      laeufeJeArm,
      fremdlastLaeufe,
      gesamtLaeufe,
      richter: richter
        ? "dasselbe Modell (Gemma 4 26B) über denselben llama-server, Server-Defaults, Urteil PASS/FAIL in Zeile 1"
        : "nicht benutzt (keine llm-Kriterien in der Suite)",
    },
    arme,
    armLabel: ARM_LABEL,
    faelle: faelleFuerBericht,
    nichtGemessen: [
      ...(suite.faelle.some((f) => f.typ === "verhalten")
        ? []
        : ["keine verhalten-Fälle in der Suite — Wirkungs-Vergleich der Arme fehlt"]),
      "Läufe hatten nur die in den Fällen konfigurierten Tools — Schreib- und Netzschritte (z. B. „Quellen verifizieren“ mit Abruf) sind nicht Teil dieser Messung",
    ],
    notizen,
    reproduktion:
      `komki up\n` +
      `node apps/komki_cli/experiments/pi_packages/skill-evals/run.mjs --skill ${args.skill} --baseline ${args.baseline}`,
    suiteSha: gitSha(),
  });

  const berichtPfad = args.bericht ?? path.join(REPO_ROOT, "skills", args.skill, "BENCHMARK.md");
  await mkdir(path.dirname(berichtPfad), { recursive: true });
  await writeFile(berichtPfad, bericht);
  await writeFile(
    path.join(root, "ergebnis.json"),
    JSON.stringify({ root, gesamtLaeufe, laufErgebnisse }, null, 2),
  );

  console.log(`\nBericht:   ${berichtPfad}`);
  console.log(`Rohdaten:  ${path.join(root, "ergebnis.json")}`);
  console.log(`Stichproben: ${path.join(root, "antworten")}`);
  console.log(`Fremdlast: ${fremdlastLaeufe}/${gesamtLaeufe} Läufe`);
}

try {
  await main();
} catch (error) {
  console.error(String(error?.stack ?? error));
  process.exitCode = 2;
}
