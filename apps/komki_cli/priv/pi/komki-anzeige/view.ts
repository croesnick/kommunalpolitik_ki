// Anzeige der Vermittler-Antworten in pi: reine Funktionen, keine Imports.
// Eingabe ist der JSON-Text, den der Vermittler als MCP-Ergebnis liefert;
// Ausgabe sind gestaltete Zeilen. Nichts hier ändert, was das Modell sieht.
//
// Regeln: Ablehnung, Zurückhaltung und Labels stehen immer sichtbar da,
// auch zugeklappt. Fremde Inhalte (RIS, Vault, Web) laufen durch clean(),
// damit sie keine Steuersequenzen ins Terminal schreiben. Unbekannte
// Antworten fallen auf das Rohformat zurück.

export interface Paint {
	fg(token: string, text: string): string;
	bold(text: string): string;
}

/** Eine Zeile vor dem Umbruch: `lead` steht links, `body` bricht mit Einzug um. */
export interface Row {
	lead?: string;
	leadWidth?: number;
	/** Lead der Folgezeilen beim Umbruch (Standard: Leerraum). */
	cont?: string;
	body: string;
}

export interface ViewOptions {
	expanded: boolean;
	expandKey: string;
}

type Json = Record<string, any>;

export const SERVER_PREFIX = "mcp__komki__";

// Bekannte Bindungen des Arbeitsraums (KomkiMediator.Templates). Unbekannte
// Labels erscheinen roh und als Warnung, nie geraten.
const LABELS: Record<string, string> = {
	"ris-oeffentlich@1": "öffentlich",
	"vault-oeffentlich@1": "öffentlich",
	"web-oeffentlich@1": "öffentlich",
	"vault-vertraulich@1": "vertraulich",
};

const BLOCKERS: Record<string, string> = {
	label_not_included: "Das Label des Inhalts ist in diesem Arbeitsraum nicht zugelassen.",
	recipient_not_allowed: "Dieser Arbeitsraum darf an diesen Empfänger nichts schicken.",
	workspace_invalid: "Der Arbeitsraum ist ungültig.",
	basis_right_false: "Die Rechtsgrundlage ist nicht erfüllt.",
	audit_path_not_ready: "Das Journal ist nicht bereit.",
	missing_operation_rule: "Für diese Operation gibt es keine Regel.",
	binding_condition_false: "Eine Bedingung der Bindung ist nicht erfüllt.",
	object_quarantine: "Der Inhalt ist noch nicht eingestuft (Quarantäne).",
	missing_fact: "Ein nötiger Nachweis fehlt.",
	recipients_unproven: "Die Empfänger sind nicht belegt.",
};

const CONNECTOR_ERRORS: Record<string, string> = {
	"upstream-error": "Quelle nicht erreichbar",
	"not-found": "nicht gefunden",
};

const SOURCES: Record<string, string> = { ris: "RIS", vault: "Vault", web: "Web" };

const GATES: Record<string, string> = { emit: "Anfrage (Gate 1)", admit: "Aufnahme der Antwort (Gate 2)" };

const COLLAPSED_HITS = 5;
const COLLAPSED_TEXT_LINES = 4;

// ---------------------------------------------------------------- Aufruf

export function callLine(toolName: string, args: Json, p: Paint): string | undefined {
	const tool = komkiTool(toolName);
	if (!tool) return undefined;
	const a = args ?? {};
	const quote = (s: unknown) => p.fg("accent", `»${clean(String(s ?? ""))}«`);
	const plain = (s: unknown) => p.fg("accent", clean(String(s ?? "")));
	const title = (s: string) => p.fg("toolTitle", p.bold(s));

	switch (tool) {
		case "ris_search":
			return `${title("RIS durchsuchen")}  ${quote(a.text)}`;
		case "ris_show":
			return `${title("RIS-Tagesordnungspunkt lesen")}  ${plain(a.top_id)}`;
		case "vault_search":
			return `${title("Vault durchsuchen")}  ${quote(a.text)}`;
		case "vault_read":
			return `${title("Vault-Notiz lesen")}  ${plain(a.note_id)}`;
		case "web_search":
			return `${title("Im Web suchen")}  ${quote(a.query)}`;
		case "vault_write_test":
			return `${title("Testnotiz anlegen")}  ${quote(a.title)}`;
		default:
			return `${title(`komki: ${tool}`)}  ${p.fg("dim", clean(JSON.stringify(a)))}`;
	}
}

// ---------------------------------------------------------------- Ergebnis

/** undefined: kein komki-Tool, pi zeichnet wie bisher. */
export function resultRows(
	toolName: string,
	text: string,
	o: ViewOptions,
	p: Paint,
): Row[] | undefined {
	const tool = komkiTool(toolName);
	if (!tool) return undefined;

	let r: Json;
	try {
		r = JSON.parse(text);
	} catch {
		return raw(text, o, p);
	}
	if (!r || typeof r !== "object" || Array.isArray(r)) return raw(text, o, p);

	const denied = outcome(tool, r, p);
	const rows = denied ?? admittedRows(tool, r, o, p);
	if (!rows) return raw(text, o, p);

	if (o.expanded) rows.push(...details(r, p));
	else if (denied) {
		const beleg = r.decision_id ? `${p.fg("dim", `Beleg ${shortId(r.decision_id)} · `)}` : "";
		rows.push({ body: "" }, { body: beleg + hint(o, p) });
	}
	return rows;
}

// Alles, was nicht "zugelassen" ist. undefined: Inhalt wurde zugelassen.
function outcome(tool: string, r: Json, p: Paint): Row[] | undefined {
	const gate = r.rule === "emit" ? "Die Anfrage hat komki nicht verlassen." : "Der Inhalt hat das Modell nicht erreicht.";

	if (r.decision === "deny" || r.decision === "indeterminate") {
		const head =
			r.decision === "deny"
				? p.fg("error", p.bold("✗ abgelehnt"))
				: p.fg("warning", p.bold("? nicht entscheidbar"));
		return [{ body: `${head}  ${p.fg("muted", gate)}` }, ...remedyRows(r, p)];
	}

	if (r.decision === "error") {
		const head = r.rule === "emit" ? "✗ abgewiesen" : "✗ Prüffehler";
		return [
			{ body: `${p.fg("error", p.bold(head))}  ${p.fg("muted", gate)}` },
			labelled("Grund", clean(String(r.detail ?? "unbekannt")), p),
		];
	}

	if (r.admitted === "redacted") {
		return [
			{ body: `${p.fg("error", p.bold("⊘ zurückgehalten"))}  ${p.fg("muted", gate)}` },
			labelled("Grund", clean(String(r.reason ?? "Prüfung nicht bestanden")), p),
		];
	}

	if (r.admitted === false) {
		const err = r.error ?? {};
		const what = CONNECTOR_ERRORS[err.code] ?? clean(String(err.code ?? "Fehler"));
		const src = SOURCES[tool.split("_")[0]] ?? "Quelle";
		return [
			{ body: `${p.fg("warning", p.bold(`! ${src}: ${what}`))}  ${p.fg("muted", "Zugelassen, aber ohne Ergebnis.")}` },
			labelled("Meldung", clean(String(err.detail ?? "")), p),
		];
	}

	if (r.decision !== "permit") return [];
	return undefined;
}

function remedyRows(r: Json, p: Paint): Row[] {
	const rows: Row[] = [];
	for (const remedy of Array.isArray(r.remedies) ? r.remedies : []) {
		rows.push(labelled("Grund", blocker(remedy), p));
		const ways = (Array.isArray(remedy.transitions) ? remedy.transitions : []).map(transition);
		if (ways.length > 0) rows.push(labelled("Möglich", ways.join(" – oder – "), p));
	}
	const auth = Array.isArray(r.relaxation_authorities) ? r.relaxation_authorities : [];
	if (auth.length > 0) rows.push(labelled("Lockern kann", auth.map((a: unknown) => clean(String(a))).join(", "), p));
	return rows;
}

function blocker(remedy: Json): string {
	if (remedy.code === "recipient_not_allowed") {
		const room = (remedy.transitions ?? []).find((t: Json) => t?.type === "neuer_raum");
		const who = (room?.required_recipients ?? []).map((r: unknown) => clean(String(r)));
		if (who.length > 0) return `Empfänger dieser Anfrage (${who.join(", ")}) sind in diesem Arbeitsraum nicht alle erlaubt.`;
	}
	return BLOCKERS[remedy.code] ?? clean(String(remedy.code));
}

function transition(t: Json): string {
	switch (t?.type) {
		case "neuer_raum": {
			const need = (t.required_bindings ?? []).map(labelName);
			return need.length > 0
				? `in einem Arbeitsraum, der „${need.join("“, „")}“ zulässt`
				: "in einem anderen Arbeitsraum";
		}
		case "aktionsfreigabe":
			return t.scope === "object"
				? `nach Einstufung von ${clean(String(t.object))} (GO)`
				: "mit einer Freigabe (GO) für genau diesen Aufruf";
		case "fakt_nachreichen":
			return `nach Nachreichen von ${(t.facts ?? []).map((f: unknown) => clean(String(f))).join(", ")}`;
		case "registrierte_transformation":
			return `über die Transformation ${clean(String(t.transformation))}`;
		default:
			return clean(String(t?.type ?? "?"));
	}
}

// ---------------------------------------------------------------- Zugelassen

function admittedRows(tool: string, r: Json, o: ViewOptions, p: Paint): Row[] | undefined {
	const hits = Array.isArray(r.results) ? r.results : undefined;
	const count = hits ? ` · ${hits.length === 0 ? "keine Treffer" : `${hits.length} Treffer`}` : "";
	const head = { body: `${p.fg("success", p.bold("✓ zugelassen"))} · ${labelBadge(r.labels, p)}${p.fg("muted", count)}` };

	let body: Row[] | undefined;
	switch (tool) {
		case "ris_search":
			body = hits && list(hits, o, p, (h) => risHit(h, o, p));
			break;
		case "web_search":
			body = hits && list(hits, o, p, (h) => webHit(h, o, p));
			break;
		case "vault_search":
			body = hits && list(hits, o, p, (h) => vaultHit(h, r.labels, p));
			break;
		case "ris_show":
			body = risShow(r, o, p);
			break;
		case "vault_read":
			body = vaultRead(r, o, p);
			break;
		case "vault_write_test":
			body = [labelled("Angelegt", p.fg("accent", clean(String(r.note_id ?? ""))), p)];
			break;
		default:
			body = [];
	}
	if (!body) return undefined;
	return [head, ...body, ...source(tool, r, o, p)];
}

function list(hits: Json[], o: ViewOptions, p: Paint, one: (h: Json) => Row[]): Row[] {
	const shown = o.expanded ? hits : hits.slice(0, COLLAPSED_HITS);
	const rows = shown.flatMap(one);
	const rest = hits.length - shown.length;
	if (rest > 0) rows.push({ body: p.fg("muted", `… ${rest} weitere`) });
	return rows;
}

function risHit(h: Json, o: ViewOptions, p: Paint): Row[] {
	return [
		{ lead: p.fg("muted", date(h.datum)), leadWidth: 12, body: title(h.titel, p) },
		{ lead: "", leadWidth: 12, body: p.fg("muted", clean(String(h.sitzung ?? ""))) },
		...urlRow(h.url, 12, o, p),
	];
}

function webHit(h: Json, o: ViewOptions, p: Paint): Row[] {
	const rows: Row[] = [{ lead: "•", leadWidth: 2, body: `${title(h.title, p)}  ${p.fg("dim", host(h.url))}` }];
	if (h.snippet) rows.push({ lead: "", leadWidth: 2, body: p.fg("muted", clean(String(h.snippet))) });
	return [...rows, ...urlRow(h.url, 2, o, p)];
}

// Volle Adresse nur aufgeklappt: zum Kopieren in Anträge und Notizen.
function urlRow(url: unknown, indent: number, o: ViewOptions, p: Paint): Row[] {
	const u = safeUrl(url);
	return o.expanded && u ? [{ lead: "", leadWidth: indent, body: p.fg("mdLinkUrl", u) }] : [];
}

function vaultHit(h: Json, overall: unknown, p: Paint): Row[] {
	const own = sameLabels(h.labels, overall) ? "" : `  ${labelBadge(h.labels, p)}`;
	return [
		{ lead: "•", leadWidth: 2, body: `${p.bold(clean(String(h.title ?? "")))}${own}` },
		{ lead: "", leadWidth: 2, body: p.fg("dim", clean(String(h.note_id ?? ""))) },
	];
}

function risShow(r: Json, o: ViewOptions, p: Paint): Row[] {
	const rows: Row[] = [
		{ body: title(r.titel, p) },
		{ body: p.fg("muted", `${clean(String(r.sitzung ?? ""))} · ${date(r.datum)}`) },
		...urlRow(r.url, 0, o, p),
	];
	const text = clean(String(r.text ?? "")).trim();
	rows.push(...excerpt(text, "Zu diesem Tagesordnungspunkt ist kein Text hinterlegt.", o, p));
	return rows;
}

function vaultRead(r: Json, o: ViewOptions, p: Paint): Row[] {
	const title = clean(String(r.title ?? ""));
	let content = clean(String(r.content ?? "")).trim();
	// Die Überschrift wiederholt meist den Titel.
	const first = content.split("\n", 1)[0];
	if (first.replace(/^#+\s*/, "") === title) content = content.slice(first.length).trim();
	return [
		{ body: p.bold(title) },
		...excerpt(content, "Die Notiz ist leer.", o, p),
	];
}

// Text als eingerückter Auszug mit Balken; Absätze bleiben, Leerzeilen
// fallen auf eine zusammen. Zugeklappt nur die ersten Zeilen.
function excerpt(text: string, empty: string, o: ViewOptions, p: Paint): Row[] {
	if (!text) return [{ body: p.fg("muted", empty) }];
	const lines = text.split("\n").filter((l, i, all) => l.trim() !== "" || all[i - 1]?.trim() !== "");
	const filled = lines.filter((l) => l.trim() !== "").length;
	let shown = lines;
	if (!o.expanded) {
		let taken = 0;
		shown = lines.filter((l) => (taken += l.trim() !== "" ? 1 : 0) <= COLLAPSED_TEXT_LINES);
		while (shown.length > 0 && shown[shown.length - 1].trim() === "") shown = shown.slice(0, -1);
	}
	const bar = p.fg("dim", "│");
	const rows: Row[] = [{ body: "" }, ...shown.map((l) => ({ lead: bar, leadWidth: 2, cont: bar, body: p.fg("text", l) }))];
	const rest = filled - shown.filter((l) => l.trim() !== "").length;
	if (rest > 0) rows.push({ lead: bar, leadWidth: 2, body: p.fg("muted", `… ${rest} weitere Zeilen`) });
	return rows;
}

// Quellenpflicht: Quelle, Abrufzeitpunkt und Beleg stehen immer da.
function source(tool: string, r: Json, o: ViewOptions, p: Paint): Row[] {
	const parts = [`Quelle: ${SOURCES[tool.split("_")[0]] ?? "komki"}`];
	if (r.abrufdatum) parts.push(`abgerufen ${timestamp(r.abrufdatum)}`);
	if (r.decision_id) parts.push(`Beleg ${shortId(r.decision_id)}`);
	const line = p.fg("dim", parts.join(" · "));
	return [{ body: "" }, { body: o.expanded ? line : `${line}${p.fg("dim", " · ")}${hint(o, p)}` }];
}

function details(r: Json, p: Paint): Row[] {
	const rows: Row[] = [{ body: "" }, { body: p.fg("muted", p.bold("Prüfdetails")) }];
	const add = (k: string, v: unknown) => {
		if (v !== undefined && v !== null && v !== "") rows.push({ lead: p.fg("muted", k), leadWidth: 18, body: p.fg("dim", clean(String(v))) });
	};
	add("Prüfschritt", GATES[r.rule] ?? r.rule);
	add("Entscheidung", r.decision);
	if (r.admitted === "redacted") add("Ergebnis", "zurückgehalten");
	add("Labels", Array.isArray(r.labels) ? r.labels.join(", ") : undefined);
	add("Beleg", r.decision_id);
	add("Beleg der Anfrage", r.emit_decision_id);
	add("Inhalts-Hash", r.payload_hash);
	add("Registry", r.registry_id);
	add("Prüfbefunde", Array.isArray(r.verify) ? r.verify.join(", ") : undefined);
	for (const remedy of Array.isArray(r.remedies) ? r.remedies : []) {
		for (const t of remedy.transitions ?? []) if (t.call_hash) add("GO bindet an", t.call_hash);
	}
	rows.push({ body: p.fg("dim", "Die Kette aller Belege prüft: komki journal verify") });
	return rows;
}

function raw(text: string, o: ViewOptions, p: Paint): Row[] {
	const lines = clean(text).split("\n");
	const shown = o.expanded ? lines : lines.slice(0, 10);
	const rows = shown.map((l) => ({ body: p.fg("toolOutput", l) }));
	if (!o.expanded && lines.length > shown.length) rows.push({ body: hint(o, p) });
	return [{ body: p.fg("warning", "Unbekannte Antwortform, unverändert angezeigt:") }, ...rows];
}

// ---------------------------------------------------------------- Bausteine

function komkiTool(toolName: string): string | undefined {
	return toolName.startsWith(SERVER_PREFIX) ? toolName.slice(SERVER_PREFIX.length) : undefined;
}

function labelled(key: string, value: string, p: Paint): Row {
	return { lead: p.fg("muted", key), leadWidth: 10, body: value };
}

function hint(o: ViewOptions, p: Paint): string {
	return p.fg("dim", `${o.expandKey}: Prüfdetails`);
}

function labelName(label: unknown): string {
	return LABELS[String(label)] ?? clean(String(label));
}

function labelBadge(labels: unknown, p: Paint): string {
	const list = Array.isArray(labels) ? labels.map(String) : [];
	if (list.length === 0) return p.fg("warning", "ohne Label");
	const names = [...new Set(list.map((l) => (l in LABELS ? p.fg("accent", LABELS[l]) : p.fg("warning", clean(l)))))];
	return names.join(", ");
}

function sameLabels(a: unknown, b: unknown): boolean {
	return JSON.stringify([...(Array.isArray(a) ? a : [])].sort()) === JSON.stringify([...(Array.isArray(b) ? b : [])].sort());
}

function title(text: unknown, p: Paint): string {
	return p.bold(clean(String(text ?? "")));
}

function safeUrl(url: unknown): string | undefined {
	const u = clean(String(url ?? ""));
	return /^https?:\/\/[^\s]+$/.test(u) ? u : undefined;
}

function host(url: unknown): string {
	const u = safeUrl(url);
	if (!u) return "";
	try {
		return new URL(u).host.replace(/^www\./, "");
	} catch {
		return "";
	}
}

function date(d: unknown): string {
	const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(d ?? ""));
	return m ? `${m[3]}.${m[2]}.${m[1]}` : clean(String(d ?? ""));
}

function timestamp(iso: unknown): string {
	const t = new Date(String(iso));
	if (Number.isNaN(t.getTime())) return clean(String(iso));
	// Feste Zeitzone: in der Sandbox ist keine gesetzt, node rechnete sonst in UTC.
	return new Intl.DateTimeFormat("de-DE", { dateStyle: "medium", timeStyle: "short", timeZone: "Europe/Berlin" }).format(t);
}

function shortId(id: unknown): string {
	const s = clean(String(id));
	return s.length > 12 ? `${s.slice(0, 12)}…` : s;
}

// Steuerzeichen (inkl. ESC) und Bidi-Overrides entfernen, Tabs zu Leerzeichen.
export function clean(s: string): string {
	return s
		.replace(/\t/g, "  ")
		.replace(/\r\n?/g, "\n")
		.replace(/[\u0000-\u0009\u000b-\u001f\u007f-\u009f‪-‮⁦-⁩]/g, "");
}

// ---------------------------------------------------------------- Umbruch

/** Zeilen auf `width` umbrechen; `wrap` und `measure` stellt der Aufrufer (ANSI-bewusst). */
export function layout(
	rows: Row[],
	width: number,
	wrap: (text: string, width: number) => string[],
	measure: (text: string) => number,
): string[] {
	const out: string[] = [];
	for (const row of rows) {
		const leadWidth = row.lead !== undefined ? Math.min(row.leadWidth ?? measure(row.lead) + 1, Math.floor(width / 2)) : 0;
		// Zu schmal für die Spalte: Lead in eine eigene Zeile.
		if (row.lead && measure(row.lead) >= leadWidth) {
			out.push(row.lead);
			out.push(...layout([{ lead: "", leadWidth, cont: row.cont, body: row.body }], width, wrap, measure));
			continue;
		}
		const bodyWidth = Math.max(1, width - leadWidth);
		const parts = row.body === "" ? [""] : wrap(row.body, bodyWidth);
		parts.forEach((part, i) => {
			const l = i === 0 ? row.lead : row.cont;
			const lead = l ? l + " ".repeat(Math.max(1, leadWidth - measure(l))) : " ".repeat(leadWidth);
			out.push(lead + part);
		});
	}
	return out;
}
