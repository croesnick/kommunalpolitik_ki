/**
 * Lädt die Eval-Suite eines Skills: skills/<name>/evals/cases/<fall>/
 * mit case.md (Frontmatter: Konfiguration, Body: Prompt), fixtures/ (in den
 * Arbeitsbereich des Laufs kopiert) und bewerter/ (je Datei ein Kriterium,
 * Frontmatter: Typ und Optionen, Body: Begründung bzw. PASS/FAIL-Bedingung).
 *
 * Die Konvention (Ort, Fallformat, Bewertertypen) steht in
 * docs/agents/skill-evals.md; dieses Modul setzt sie durch: unbekannte Felder
 * und Typen, leere Optionen oder ein fehlender Trigger-/Negativfall sind
 * Fehler. Bewerterdefinitionen gehören zur Suite — der Runner kennt die Typen,
 * aber keine Kriterien.
 */
import { readdir, readFile } from "node:fs/promises";
import path from "node:path";

import { parseFrontmatter } from "./yaml.mjs";

export const FALL_TYPEN = ["verhalten", "trigger", "negativ"];
export const BEWERTER_TYPEN = [
  "enthaelt",
  "enthaelt-nicht",
  "zahlen",
  "tool-call",
  "datei",
  "llm",
];

/** Standard-Unterordnernamen je Skill-Suite. */
export function suitePfad(repoRoot, skillName) {
  return path.join(repoRoot, "skills", skillName, "evals");
}

function verlangteFelder(file, felder, key, typname) {
  if (!(key in felder) || felder[key] === "" || felder[key] === null) {
    throw new Error(`${file}: Pflichtfeld "${key}" für Bewerter-Typ ${typname} fehlt`);
  }
}

async function leseVerzeichnis(dir) {
  try {
    return (await readdir(dir, { withFileTypes: true })).sort((a, b) =>
      a.name.localeCompare(b.name),
    );
  } catch {
    return [];
  }
}

/** Alle Fixture-Dateien eines Falls rekursiv einsammeln (relativ zum Fall). */
async function leseFixtures(fallDir) {
  const fixtures = [];
  async function walk(relDir) {
    for (const entry of await leseVerzeichnis(path.join(fallDir, relDir))) {
      const rel = relDir ? path.join(relDir, entry.name) : entry.name;
      if (entry.isDirectory()) await walk(rel);
      else fixtures.push(rel);
    }
  }
  await walk("fixtures");
  return fixtures;
}

async function ladeBewerter(fallDir, fallId) {
  const bewerter = [];
  const dir = path.join(fallDir, "bewerter");
  for (const entry of await leseVerzeichnis(dir)) {
    if (!entry.isFile() || !entry.name.endsWith(".md")) continue;
    const file = path.join(dir, entry.name);
    const { felder, rest } = parseFrontmatter(await readFile(file, "utf8"), file);
    const id = felder.id;
    if (typeof id !== "string" || id.trim() === "") {
      throw new Error(`${file}: Bewerter braucht ein Feld "id"`);
    }
    const typ = felder.typ;
    if (!BEWERTER_TYPEN.includes(typ)) {
      throw new Error(
        `${file}: unbekannter Bewerter-Typ "${typ}" — bekannt: ${BEWERTER_TYPEN.join(", ")}`,
      );
    }

    const b = {
      id,
      typ,
      // Body: Begründung des Kriteriums ( landet im Bericht) bzw. bei llm die
      // konkrete PASS/FAIL-Bedingung für den Richter.
      text: rest.trim(),
      quelle: path.relative(fallDir, file),
    };

    if (typ === "enthaelt" || typ === "enthaelt-nicht") {
      verlangteFelder(file, felder, "optionen", typ);
      if (!Array.isArray(felder.optionen) || felder.optionen.length === 0) {
        throw new Error(`${file}: "optionen" muss eine nicht leere Liste sein`);
      }
      b.optionen = felder.optionen.map(String);
      b.min_treffer = Number(felder.min_treffer ?? 1);
    } else if (typ === "zahlen") {
      b.kennzeichne_abgeleitet = felder.kennzeichne_abgeleitet === true;
      b.abgeleitet_vermerke = (felder.abgeleitet_vermerke ?? ["abgeleitet"]).map(String);
    } else if (typ === "tool-call") {
      verlangteFelder(file, felder, "tool", typ);
      b.tool = String(felder.tool);
      b.parameter = felder.parameter === undefined ? ".*" : String(felder.parameter);
      b.anzahl_min = felder.anzahl_min === undefined ? 1 : Number(felder.anzahl_min);
      b.anzahl_max =
        felder.anzahl_max === undefined ? Number.POSITIVE_INFINITY : Number(felder.anzahl_max);
    } else if (typ === "datei") {
      verlangteFelder(file, felder, "datei", typ);
      b.datei = String(felder.datei);
    } else if (typ === "llm") {
      if (b.text.length === 0) {
        throw new Error(`${file}: llm-Bewerter braucht im Body konkrete PASS/FAIL-Bedingungen`);
      }
    }

    const erlaubt = new Set([
      "id",
      "typ",
      "optionen",
      "min_treffer",
      "kennzeichne_abgeleitet",
      "abgeleitet_vermerke",
      "tool",
      "parameter",
      "anzahl_min",
      "anzahl_max",
      "datei",
    ]);
    for (const key of Object.keys(felder)) {
      if (!erlaubt.has(key)) {
        throw new Error(`${file}: unbekanntes Feld "${key}" im Bewerter`);
      }
    }
    bewerter.push(b);
  }
  if (bewerter.length === 0) {
    throw new Error(`${fallDir}: Fall "${fallId}" hat keine Bewerter`);
  }
  const ids = new Set(bewerter.map((b) => b.id));
  if (ids.size !== bewerter.length) {
    throw new Error(`${fallDir}: Bewerter-IDs sind nicht eindeutig`);
  }
  return bewerter;
}

/**
 * Lädt alle Fälle einer Suite. Rückgabe:
 * { faelle: [{ id, typ, beschreibung, arme, tools, timeoutS, laeufe, quelle,
 *              prompt, fixtures: [name], bewerter: [...] }] }
 */
export async function ladeSuite(repoRoot, skillName, auswahl = null) {
  const suiteDir = suitePfad(repoRoot, skillName);
  const faelle = [];
  for (const entry of await leseVerzeichnis(path.join(suiteDir, "cases"))) {
    if (!entry.isDirectory()) continue;
    const fallDir = path.join(suiteDir, "cases", entry.name);
    const caseFile = path.join(fallDir, "case.md");
    let raw;
    try {
      raw = await readFile(caseFile, "utf8");
    } catch {
      throw new Error(`${fallDir}: case.md fehlt`);
    }
    const { felder, rest } = parseFrontmatter(raw, caseFile);

    const id = felder.id;
    if (id !== entry.name) {
      throw new Error(`${caseFile}: Feld "id" ("${id}") muss der Verzeichnisname ("${entry.name}") sein`);
    }
    const typ = felder.typ;
    if (!FALL_TYPEN.includes(typ)) {
      throw new Error(
        `${caseFile}: unbekannter Fall-Typ "${typ}" — bekannt: ${FALL_TYPEN.join(", ")}`,
      );
    }
    if (auswahl && !auswahl.has(id)) continue;

    const beschreibung = felder.beschreibung;
    if (typeof beschreibung !== "string" || beschreibung.trim() === "") {
      throw new Error(`${caseFile}: Pflichtfeld "beschreibung" fehlt`);
    }
    const prompt = rest.trim();
    if (prompt.length === 0) {
      throw new Error(`${caseFile}: Body (der Prompt) ist leer`);
    }

    let arme = Array.isArray(felder.arme) ? felder.arme.map(String) : null;
    if (typ === "verhalten") {
      arme = arme ?? ["ohne-skill", "vorige", "aktuelle"];
      const erlaubt = new Set(["ohne-skill", "vorige", "aktuelle"]);
      for (const arm of arme) {
        if (!erlaubt.has(arm)) {
          throw new Error(`${caseFile}: unbekannter Arm "${arm}" für Typ verhalten`);
        }
      }
      if (!arme.includes("aktuelle")) {
        throw new Error(`${caseFile}: verhalten-Fall braucht den Arm "aktuelle"`);
      }
    } else {
      // trigger/negativ laufen nur mit dem echten Skill-Mechanismus — da gibt
      // es genau einen Arm.
      arme = ["aktuelle"];
    }

    const erlaubteFelder = new Set([
      "id",
      "typ",
      "beschreibung",
      "arme",
      "tools",
      "timeout_s",
      "laeufe",
      "quelle",
    ]);
    for (const key of Object.keys(felder)) {
      if (!erlaubteFelder.has(key)) {
        throw new Error(`${caseFile}: unbekanntes Feld "${key}" im Fall`);
      }
    }

    faelle.push({
      id,
      typ,
      beschreibung,
      arme,
      tools: typeof felder.tools === "string" ? felder.tools : String(felder.tools ?? "read"),
      timeoutS: Number(felder.timeout_s ?? 300),
      laeufe: Number(felder.laeufe ?? 5),
      quelle: typeof felder.quelle === "string" ? felder.quelle : null,
      prompt,
      fixtures: await leseFixtures(fallDir),
      bewerter: await ladeBewerter(fallDir, id),
    });
  }

  if (faelle.length === 0) {
    throw new Error(`${suiteDir}: keine Fälle gefunden`);
  }
  if (!auswahl) {
    const typen = new Set(faelle.map((fall) => fall.typ));
    if (!typen.has("trigger") || !typen.has("negativ")) {
      throw new Error(
        `${suiteDir}: Suite braucht mindestens einen Trigger- und einen Negativfall (Pflicht je Skill)`,
      );
    }
  }
  return { skill: skillName, faelle };
}
