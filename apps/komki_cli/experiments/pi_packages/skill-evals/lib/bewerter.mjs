/**
 * Bewerter für die Skill-Evals (Ticket #292).
 *
 * Jeder Bewerter ist eine Datei in der Suite (skills/<name>/evals/cases/<fall>/
 * bewerter/<id>.md) — Typ und Optionen stehen dort in der Frontmatter, nicht
 * hier. Dieses Modul kennt nur die Typen:
 *
 *   enthaelt        Antwort muss mindestens min_treffer der Optionen (Regex,
 *                   Groß-/Kleinschreibung egal) enthalten. Wortstellungstoleranz
 *                   über Alternativen in den Optionen („Förder… Frist“ und
 *                   „Frist … Förder“), nie über weichere Kriterien.
 *   enthaelt-nicht  Antwort darf keine der Optionen enthalten.
 *   zahlen          keine erfundenen Zahlen: classifyNumbers (factTokens aus
 *                   smoke/fixtures.mjs) gegen den Fixture-Text; abgeleitete
 *                   (Summe/Differenz aus Quellenzahlen) sind toleriert und
 *                   werden protokolliert; mit kennzeichne_abgeleitet müssen sie
 *                   in der Antwort als abgeleitet vermerkt sein.
 *   tool-call       ein Tool-Aufruf (Name + Parameter-Regex gegen die
 *                   Argumente) muss anzahl_min … anzahl_max Mal vorkommen.
 *   datei           eine Datei muss im Arbeitsverzeichnis des Laufs entstanden
 *                   sein.
 *   llm             ein Richter-LLM (dasselbe lokale Modell) urteilt über
 *                   kurze Ausgaben gegen konkrete PASS/FAIL-Bedingungen aus
 *                   dem Body der Bewerter-Datei.
 */
import http from "node:http";

import { classifyNumbers } from "../../smoke/fixtures.mjs";

const ANTWORT_GRENZE_FUER_RICHTER = 4000;

function trefferVonOptionen(antwort, optionen) {
  return optionen.filter((option) => {
    try {
      return new RegExp(option, "i").test(antwort);
    } catch (error) {
      throw new Error(`Bewerter-Option ist kein Regex: "${option}" (${error.message})`);
    }
  });
}

/**
 * Bewertet einen Bewerter gegen den Lauf-Kontext.
 * kontext: { antwort, toolCalls, dateien, quelle, richter }
 *   antwort:  letzter Assistant-Text (oder "")
 *   toolCalls: validateToolCalls-Ergebnis (smoke/measure.mjs)
 *   dateien:  im Lauf neu entstandene Dateien, relativ zum Run-Verzeichnis
 *   quelle:   konkatenierter Fixture-Text des Falls
 *   richter:  async (bedingungen, antwort) => { pass, text, usage }
 * Rückgabe: { bestanden, details }
 */
export async function bewerte(b, kontext) {
  const antwort = kontext.antwort ?? "";
  switch (b.typ) {
    case "enthaelt": {
      const treffer = trefferVonOptionen(antwort, b.optionen);
      return { bestanden: treffer.length >= b.min_treffer, details: { treffer } };
    }
    case "enthaelt-nicht": {
      const treffer = trefferVonOptionen(antwort, b.optionen);
      return { bestanden: treffer.length === 0, details: { treffer } };
    }
    case "zahlen": {
      const { erfunden, abgeleitet } = classifyNumbers(kontext.quelle ?? "", antwort);
      let bestanden = erfunden.length === 0;
      let kennzeichnung = null;
      if (bestanden && b.kennzeichne_abgeleitet && abgeleitet.length > 0) {
        kennzeichnung = trefferVonOptionen(antwort, b.abgeleitet_vermerke).length > 0;
        bestanden = kennzeichnung;
      }
      return { bestanden, details: { erfunden, abgeleitet, kennzeichnung } };
    }
    case "tool-call": {
      const parameterRe = new RegExp(b.parameter, "i");
      const treffer = [];
      for (const call of kontext.toolCalls ?? []) {
        if (call.name !== b.tool) continue;
        const haystacks = [call.rawArguments ?? "", JSON.stringify(call.args ?? {})];
        if (haystacks.some((hay) => parameterRe.test(hay))) treffer.push(call);
      }
      const bestanden = treffer.length >= b.anzahl_min && treffer.length <= b.anzahl_max;
      return {
        bestanden,
        details: {
          anzahl: treffer.length,
          unguelig: treffer.filter((call) => !call.valid).length,
          argumente: treffer.map((call) => call.rawArguments ?? call.args ?? null),
        },
      };
    }
    case "datei": {
      const gefundene = (kontext.dateien ?? []).filter((datei) => datei.endsWith(`work/${b.datei}`));
      return { bestanden: gefundene.length > 0, details: { gefundene } };
    }
    case "llm": {
      const urteil = await kontext.richter(b.text, antwort);
      return { bestanden: urteil.pass, details: { urteil } };
    }
    default:
      throw new Error(`unbekannter Bewerter-Typ: ${b.typ}`);
  }
}

/**
 * Richter-LLM über denselben llama-server: kurzer, deterministisch parsebarer
 * Aufruf, Antwort nur PASS/FAIL in der ersten Zeile. Der Richter ist gepinnt
 * (dasselbe Modell, Server-Defaults) und geht in die Token-Zählung des
 * Berichts ein.
 */
export function starteRichter({ baseUrl, apiKey, model, timeoutMs = 60_000 }) {
  const url = new URL(baseUrl);
  const laeufe = [];
  const richter = (bedingungen, antwort) =>
    new Promise((resolve) => {
      const body = JSON.stringify({
        model,
        max_tokens: 256,
        messages: [
          {
            role: "system",
            content:
              "Du bist ein Bewerter für Antworten eines Sprachmodells. Du liest eine Bedingung und eine Antwort und fällst genau ein Urteil. Antworte in der ersten Zeile ausschließlich mit PASS oder FAIL, danach ein Satz Begründung.",
          },
          {
            role: "user",
            content:
              `<bedingung>\n${bedingungen}\n</bedingung>\n\n` +
              `<antwort>\n${antwort.slice(0, ANTWORT_GRENZE_FUER_RICHTER)}\n</antwort>\n\n` +
              "Urteil (erste Zeile: PASS oder FAIL):",
          },
        ],
      });
      const started = Date.now();
      const req = http.request(
        {
          hostname: url.hostname,
          port: Number(url.port),
          method: "POST",
          path: `${url.pathname.replace(/\/$/, "")}/chat/completions`,
          headers: {
            "content-type": "application/json",
            authorization: `Bearer ${apiKey}`,
            "content-length": Buffer.byteLength(body),
          },
        },
        (res) => {
          const chunks = [];
          res.on("data", (chunk) => chunks.push(chunk));
          res.on("end", () => {
            const text = Buffer.concat(chunks).toString("utf8");
            let pass = null;
            let urteilstext = "";
            let usage = null;
            try {
              const parsed = JSON.parse(text);
              urteilstext = parsed.choices?.[0]?.message?.content ?? "";
              usage = parsed.usage ?? null;
            } catch {
              urteilstext = text.slice(0, 500);
            }
            const erste = (urteilstext.trim().split("\n")[0] ?? "").trim().toUpperCase();
            if (erste.startsWith("PASS")) pass = true;
            else if (erste.startsWith("FAIL")) pass = false;
            laeufe.push({ durationMs: Date.now() - started, usage });
            resolve({ pass: pass === true, unbestimmt: pass === null, text: urteilstext, usage });
          });
        },
      );
      req.setTimeout(timeoutMs, () => {
        req.destroy();
        laeufe.push({ durationMs: Date.now() - started, usage: null });
        resolve({ pass: false, unbestimmt: true, text: "timeout", usage: null });
      });
      req.on("error", (error) => {
        laeufe.push({ durationMs: Date.now() - started, usage: null });
        resolve({ pass: false, unbestimmt: true, text: String(error?.message ?? error), usage: null });
      });
      req.end(body);
    });
  richter.laeufe = laeufe;
  return richter;
}
