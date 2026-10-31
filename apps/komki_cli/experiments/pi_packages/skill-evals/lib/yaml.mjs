/**
 * Minimaler YAML-Frontmatter-Parser für die Skill-Eval-Suiten (Ticket #292).
 *
 * Bewusst ohne Abhängigkeit: Die Frontmatter der Fälle und Bewerter brauchen
 * nur einen kleinen YAML-Dialekt — Skalare, gefaltete Blockskalare (> und |),
 * Flow-Listen [a, b] und Block-Listen (- a). Alles andere ist ein Fehler mit
 * Datei und Zeile, damit ein Tippfehler in einem Kriterium laut auffällt,
 * statt still als String durchzurutschen.
 *
 * parseFrontmatter(text) → { felder, rest }
 *   felder: Objekt (Werte: string | number | string[])
 *   rest:   Text nach der Frontmatter (der Prompt bzw. die Bedingung)
 */

function fail(file, line, message) {
  throw new Error(`${file}:${line}: ${message}`);
}

/** Einzelnen Skalarwert parsen: Zahl, Flow-Liste oder (quoted) String. */
function parseScalar(file, line, raw) {
  const text = raw.trim();
  if (text.startsWith("[") && text.endsWith("]")) {
    const inner = text.slice(1, -1).trim();
    if (inner.length === 0) return [];
    return inner.split(",").map((item) => unquote(item.trim()));
  }
  if (/^-?\d+$/.test(text)) return Number(text);
  return unquote(text);
}

/** Anführungszeichen strippen; normale Quotes dürfen KEINE Sonderbedeutung haben. */
function unquote(text) {
  if (
    (text.startsWith('"') && text.endsWith('"') && text.length >= 2) ||
    (text.startsWith("'") && text.endsWith("'") && text.length >= 2)
  ) {
    return text.slice(1, -1);
  }
  return text;
}

/** Zeilen eines Blockskalars (> gefaltet, | wörtlich) einsammeln. */
function blockScalar(lines, start, folded) {
  const out = [];
  let i = start;
  while (i < lines.length && (lines[i].trim() === "" || /^[ ]+/.test(lines[i]))) {
    out.push(lines[i].replace(/^[ ]+/, ""));
    i += 1;
  }
  const content = out.join(folded ? " " : "\n").replace(/\s+$/, "");
  return { value: content, next: i };
}

export function parseFrontmatter(source, file = "<text>") {
  const text = source.replace(/\r\n/g, "\n");
  if (!text.startsWith("---\n")) {
    fail(file, 1, "Frontmatter fehlt: Datei muss mit einer --- -Zeile beginnen");
  }
  const endMatch = text.match(/\n---\s*\n/);
  if (!endMatch || endMatch.index === undefined) {
    fail(file, 1, "Frontmatter nicht geschlossen: zweite --- -Zeile fehlt");
  }
  const rawFm = text.slice(4, endMatch.index);
  const rest = text.slice(endMatch.index + endMatch[0].length);

  const lines = rawFm.split("\n");
  const felder = {};
  let i = 0;
  while (i < lines.length) {
    const line = lines[i];
    if (line.trim() === "" || line.trim().startsWith("#")) {
      i += 1;
      continue;
    }
    const match = /^([A-Za-z_][A-Za-z0-9_]*):\s*(.*)$/.exec(line);
    if (!match) {
      fail(file, i + 1, `unverständige Zeile in der Frontmatter: "${line.trim()}"`);
    }
    const key = match[1];
    let value = match[2].trim();

    if (value === ">" || value === "|" || value === ">-" || value === "|-") {
      const folded = value.startsWith(">");
      const scalar = blockScalar(lines, i + 1, folded);
      felder[key] = scalar.value;
      i = scalar.next;
      continue;
    }

    if (value === "") {
      // Block-Liste: Folgezeilen beginnen mit "  - " (Einrückung beliebig).
      const items = [];
      let j = i + 1;
      while (j < lines.length && (lines[j].trim() === "" || /^\s*- /.test(lines[j]))) {
        if (lines[j].trim() !== "") {
          const item = lines[j].replace(/^\s*- /, "").trim();
          if (item.length > 0) items.push(unquote(item));
        }
        j += 1;
      }
      if (items.length === 0) {
        fail(file, i + 1, `Feld "${key}" ist leer — entweder Wert, Flow-Liste oder "- "-Liste`);
      }
      felder[key] = items;
      i = j;
      continue;
    }

    // Kommentar am Ende einer Wertzeile abschneiden (nur außerhalb von Quotes).
    if (!value.startsWith('"') && !value.startsWith("'")) {
      const hash = value.indexOf(" #");
      if (hash !== -1) value = value.slice(0, hash).trim();
    }
    felder[key] = parseScalar(file, i + 1, value);
    i += 1;
  }
  return { felder, rest };
}
