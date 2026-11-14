/**
 * Must-have criteria K1–K8 for agenda item summaries (task 1), shared by
 * run-top-bench.mjs (#158) and the blind A/B grading in grade-ab.mjs
 * (#285). Where the criteria come from: header comment of run-top-bench.mjs.
 */
import { TOP_3_ANHOERUNG, factTokens } from "./fixtures.mjs";

// Must-have criteria as groups of alternatives (at least one option must
// occur in the answer text). K7 counts components.
export const KRITERIEN = [
  { id: "K1", label: "Gremium", options: ["Ausschuss"] },
  { id: "K2", label: "Sitzungsdatum", options: ["12.11.2026", "12. November 2026", "12. November"] },
  { id: "K3", label: "Vorhaben benannt", options: ["Bahnhofstraße", "Bahnhofstrasse"] },
  {
    id: "K4",
    label: "Anliegen erkennbar",
    options: ["Umgestaltung", "Gehweg", "Radweg", "Protected Bike", "Straßenbäume", "Stellplätze"],
  },
  { id: "K5", label: "Gesamtkosten", options: ["240.000", "240000", "240 000", "240 Tausend"] },
  {
    id: "K6",
    label: "Finanzierungsstruktur (Eigenanteil/Förderanteil)",
    options: ["80.000", "80000", "80 000", "80 Tausend", "Eigenanteil"],
  },
];

export const K7_KOMPONENTEN = ["Zustimmung", "Haushaltsplanung", "Ergänzungsantrag"];

/**
 * K8: numbers in the answer that neither occur in the source nor follow as
 * the sum or difference of two source numbers. Returns
 * { erfunden: [], abgeleitet: [] } (invented, derived; normalized tokens).
 */
export function classifyNumbers(sourceText, answerText) {
  const source = [...factTokens(sourceText)].map(Number).filter(Number.isFinite);
  const derivedSet = new Set();
  for (let i = 0; i < source.length; i += 1) {
    for (let j = 0; j < source.length; j += 1) {
      if (i === j) continue;
      derivedSet.add(source[i] - source[j]);
      derivedSet.add(source[i] + source[j]);
    }
  }
  const erfunden = [];
  const abgeleitet = [];
  for (const token of factTokens(answerText)) {
    const value = Number(token);
    if (!Number.isFinite(value)) continue;
    if (source.includes(value)) continue;
    if (derivedSet.has(value)) abgeleitet.push(token);
    else erfunden.push(token);
  }
  return { erfunden: [...new Set(erfunden)], abgeleitet: [...new Set(abgeleitet)] };
}

export function checkAnswer(answer) {
  const erfuellt = {};
  for (const kriterium of KRITERIEN) {
    erfuellt[kriterium.id] = kriterium.options.some((option) => answer.includes(option));
  }
  const k7Hits = K7_KOMPONENTEN.filter((option) =>
    answer.toLowerCase().includes(option.toLowerCase()),
  );
  erfuellt.K7 = k7Hits.length >= 2;
  const k7Komponenten = k7Hits;
  const zahlen = classifyNumbers(TOP_3_ANHOERUNG, answer);
  erfuellt.K8 = zahlen.erfunden.length === 0;
  return { erfuellt, k7Komponenten, zahlen };
}
