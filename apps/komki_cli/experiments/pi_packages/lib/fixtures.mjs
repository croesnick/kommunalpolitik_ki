import { mkdir, writeFile } from "node:fs/promises";
import path from "node:path";

/** Build a deterministic one-page PDF with WinAnsi text. No external tools. */
export function buildPdf(text = "TOP 1 Bahnhofstraße") {
  const content = `BT\n/F1 18 Tf\n72 720 Td\n(${pdfEscape(text)}) Tj\nET\n`;
  const contentBuffer = Buffer.from(content, "latin1");
  const objects = [
    Buffer.from("<< /Type /Catalog /Pages 2 0 R >>", "latin1"),
    Buffer.from("<< /Type /Pages /Kids [3 0 R] /Count 1 >>", "latin1"),
    Buffer.from(
      "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>",
      "latin1",
    ),
    Buffer.from(
      "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>",
      "latin1",
    ),
    Buffer.concat([
      Buffer.from(`<< /Length ${contentBuffer.length} >>\nstream\n`, "latin1"),
      contentBuffer,
      Buffer.from("endstream", "latin1"),
    ]),
  ];

  const chunks = [Buffer.from("%PDF-1.4\n%\xE2\xE3\xCF\xD3\n", "latin1")];
  const offsets = [0];
  let offset = chunks[0].length;
  for (const [i, object] of objects.entries()) {
    offsets.push(offset);
    const body = Buffer.concat([
      Buffer.from(`${i + 1} 0 obj\n`, "latin1"),
      object,
      Buffer.from("\nendobj\n", "latin1"),
    ]);
    chunks.push(body);
    offset += body.length;
  }
  const xrefOffset = offset;
  const xrefLines = [
    "xref",
    `0 ${objects.length + 1}`,
    "0000000000 65535 f ",
  ];
  for (let i = 1; i <= objects.length; i += 1) {
    xrefLines.push(`${String(offsets[i]).padStart(10, "0")} 00000 n `);
  }
  xrefLines.push(
    "trailer",
    `<< /Size ${objects.length + 1} /Root 1 0 R >>`,
    "startxref",
    String(xrefOffset),
    "%%EOF",
    "",
  );
  chunks.push(Buffer.from(xrefLines.join("\n"), "latin1"));
  return Buffer.concat(chunks);
}

function pdfEscape(text) {
  // ß is 0xDF in WinAnsiEncoding. Escape PDF string delimiters.
  return text
    .replace(/\\/g, "\\\\")
    .replace(/\(/g, "\\(")
    .replace(/\)/g, "\\)");
}

export async function writePdfFixture(file, text) {
  await mkdir(path.dirname(file), { recursive: true });
  await writeFile(file, buildPdf(text));
  return file;
}

export async function writeTextFile(file, text) {
  await mkdir(path.dirname(file), { recursive: true });
  await writeFile(file, text);
  return file;
}

export function fillerBytes(targetBytes, line = "Kontextzeile für den Kompaktionstest.") {
  const unit = `${line}\n`;
  const repeats = Math.ceil(targetBytes / Buffer.byteLength(unit));
  return unit.repeat(repeats);
}

/** Minimal v3 session with one German exchange, suitable for anchor search. */
export async function writeSessionFixture(file, { cwd = "/tmp/work", text = "Bitte prüfe den TOP 1 Bahnhofstraße für die Sitzung." } = {}) {
  await mkdir(path.dirname(file), { recursive: true });
  const now = new Date().toISOString();
  const header = {
    type: "session",
    version: 3,
    id: "fixture-session",
    timestamp: now,
    cwd,
  };
  const user = {
    type: "message",
    id: "u1",
    parentId: null,
    timestamp: now,
    message: {
      role: "user",
      content: text,
      timestamp: Date.now(),
    },
  };
  const assistant = {
    type: "message",
    id: "a1",
    parentId: "u1",
    timestamp: now,
    message: {
      role: "assistant",
      content: [{ type: "text", text: "Verstanden, ich prüfe den Bahnhofstraße-Tagesordnungspunkt." }],
      api: "openai-completions",
      provider: "mock",
      model: "mock-model",
      usage: { input: 1, output: 1, cacheRead: 0, cacheWrite: 0, totalTokens: 2, cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 } },
      stopReason: "stop",
      timestamp: Date.now(),
    },
  };
  await writeFile(file, [header, user, assistant].map((x) => JSON.stringify(x)).join("\n") + "\n");
  return file;
}
