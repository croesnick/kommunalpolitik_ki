// Raum, Labels und Raumdokumente in der pi-Session (Ticket #242): reine
// Funktionen wie in view.ts. Eingabe ist das Raumbild, das komki vor dem
// Start schreibt (KomkiCli.Raumbild), und die Dokumentliste, die pi zuletzt
// über list_documents bekommen hat. Nichts hier erreicht das Modell.
//
// Das Raumbild beschreibt den Raum, es entscheidet nichts: Ob ein Aufruf
// läuft, entscheidet der Vermittler.

import { clean, labelBadge, labelled, labelName, type Paint, type RoomDocument, type Row } from "./view.ts";

export interface Raum {
	raum: string | null;
	zweck: string | null;
	labels: { id: string; bezeichnung: string | null; intern: boolean | null }[];
	nach_draussen: { empfaenger: string; offen: boolean }[];
}

const ZWECKE: Record<string, string> = {
	"offene-recherche": "offene Recherche",
	sitzungsvorbereitung: "Sitzungsvorbereitung",
	vertraulich: "vertrauliche Arbeit",
};

const EMPFAENGER: Record<string, string> = {
	"brave-search": "Websuche",
	"ris-betreiber": "RIS",
};

const BEFEHLE: [string, string][] = [
	["/sitzungsmappe", "Sitzungsmappe aus den Raumdokumenten"],
	["/zusammenfassen", "ein Dokument, einen Tagesordnungspunkt oder eine Notiz zusammenfassen"],
	["/quellen", "Quellenliste aus dem bisherigen Verlauf"],
	["/raum", "Raum, Zweck, Labels und Weg nach draußen"],
	["/dokumente", "die Raumdokumente, die pi zuletzt aufgelistet hat"],
	["/hilfe", "diese Übersicht"],
];

/** Raumbild aus raum.json; undefined, wenn die Datei fehlt oder eine andere Form hat. */
export function parseRaum(text: string | undefined): Raum | undefined {
	if (!text) return undefined;
	try {
		const r = JSON.parse(text);
		if (r?.schema !== "komki-raum/1") return undefined;
		return {
			raum: typeof r.raum === "string" ? clean(r.raum) : null,
			zweck: typeof r.zweck === "string" ? clean(r.zweck) : null,
			labels: (Array.isArray(r.labels) ? r.labels : []).map((l: any) => ({
				id: clean(String(l?.id ?? "")),
				bezeichnung: typeof l?.bezeichnung === "string" ? clean(l.bezeichnung) : null,
				intern: typeof l?.intern === "boolean" ? l.intern : null,
			})),
			nach_draussen: (Array.isArray(r.nach_draussen) ? r.nach_draussen : []).map((e: any) => ({
				empfaenger: clean(String(e?.empfaenger ?? "")),
				offen: e?.offen === true,
			})),
		};
	} catch {
		return undefined;
	}
}

export function raumName(r: Raum | undefined): string {
	return r?.raum ? `Raum ${r.raum}` : "eigener Raum";
}

function zweck(r: Raum): string | undefined {
	return r.zweck ? (ZWECKE[r.zweck] ?? r.zweck.replace(/-/g, " ")) : undefined;
}

function empfaenger(id: string): string {
	return EMPFAENGER[id] ?? id;
}

function aufzaehlung(namen: string[]): string {
	return namen.length <= 1 ? namen.join("") : `${namen.slice(0, -1).join(", ")} und ${namen[namen.length - 1]}`;
}

/** Ein Satz zum Weg nach draußen; undefined, wenn das Raumbild keine Empfänger kennt. */
export function draussen(r: Raum): { offen: boolean; satz: string } | undefined {
	const alle = r.nach_draussen;
	if (alle.length === 0) return undefined;
	const offen = alle.filter((e) => e.offen).map((e) => empfaenger(e.empfaenger));
	const zu = alle.filter((e) => !e.offen).map((e) => empfaenger(e.empfaenger));
	if (zu.length === 0) return { offen: true, satz: `offen für ${aufzaehlung(offen)}` };
	const go = "einzelne Aufrufe nur mit deinem GO im komki-Fenster";
	if (offen.length === 0) return { offen: false, satz: `gesperrt, ${go}` };
	return { offen: false, satz: `offen für ${aufzaehlung(offen)}; ${aufzaehlung(zu)} gesperrt, ${go}` };
}

// Labels als Wörter, ohne Dopplungen: „öffentlich, vertraulich“.
function labelWoerter(r: Raum, p: Paint): string {
	return labelBadge(
		r.labels.map((l) => l.id),
		p,
	);
}

/** Kopfzeile zum Session-Start: ersetzt pis englischen Startbildschirm. */
export function headerRows(r: Raum | undefined, p: Paint): Row[] {
	const rows: Row[] = [{ body: `${p.fg("accent", p.bold("komki"))}  ${p.fg("muted", "Arbeitsraum für die Ratsarbeit")}` }];
	if (!r) {
		rows.push({ body: p.fg("warning", "Das Raumbild fehlt. Was pi darf, entscheidet weiter der Vermittler.") });
	} else {
		const z = zweck(r);
		rows.push({ body: `${p.bold(raumName(r))}${z ? p.fg("muted", ` · Zweck: ${z}`) : ""}` });
		if (r.labels.length > 0) rows.push(labelled("Labels", labelWoerter(r, p), p));
		const d = draussen(r);
		if (d) rows.push(labelled("Draußen", d.offen ? p.fg("text", d.satz) : p.fg("warning", d.satz), p));
	}
	rows.push(
		labelled("Dokumente", p.fg("muted", "pi findet sie mit list_documents; /dokumente zeigt die letzte Liste"), p),
		labelled("Befehle", BEFEHLE.map(([b]) => p.fg("accent", b)).join(" "), p),
	);
	return rows;
}

/** Kurzer Text für die Fußzeile. */
export function statusText(r: Raum | undefined, docs: RoomDocument[] | undefined): string {
	const parts = [raumName(r)];
	const d = r && draussen(r);
	if (d) parts.push(d.offen ? "nach draußen offen" : "nach draußen nur mit GO");
	if (docs) parts.push(docs.length === 1 ? "1 Raumdokument" : `${docs.length} Raumdokumente`);
	return parts.join(" · ");
}

/** /raum: alles aus dem Raumbild, mit den Bezeichnungen aus dem Label-Store. */
export function raumRows(r: Raum | undefined, p: Paint): Row[] {
	if (!r) return [{ body: p.fg("warning", "Das Raumbild fehlt. Was pi darf, entscheidet weiter der Vermittler.") }];
	const rows: Row[] = [{ body: p.bold(raumName(r)) }];
	const z = zweck(r);
	if (z) rows.push(labelled("Zweck", z, p));
	for (const l of r.labels) {
		const was = l.bezeichnung ?? l.id;
		const wer = l.intern === true ? p.fg("muted", " · nur du und pi") : "";
		rows.push(labelled("Label", `${p.fg("accent", labelName(l.id))}  ${was}${wer}`, p));
	}
	const d = draussen(r);
	if (d) rows.push(labelled("Draußen", d.satz, p));
	rows.push({ body: "" }, { body: p.fg("dim", "Was pi darf, entscheidet der Vermittler bei jedem Aufruf; jede Entscheidung steht im Journal.") });
	return rows;
}

/** /dokumente: die letzte Liste aus list_documents, ohne Inhalte. */
export function dokumenteRows(docs: RoomDocument[] | undefined, p: Paint): Row[] {
	if (!docs)
		return [
			{ body: p.fg("muted", "pi hat die Raumdokumente in dieser Session noch nicht aufgelistet.") },
			{ body: p.fg("muted", "Bitte pi zum Beispiel: Welche Dokumente liegen bereit. Oder starte /sitzungsmappe.") },
		];
	if (docs.length === 0) return [{ body: p.fg("muted", "In diesem Arbeitsraum liegt kein Dokument, das pi lesen kann.") }];
	return [
		{ body: p.bold(docs.length === 1 ? "1 Raumdokument" : `${docs.length} Raumdokumente`) },
		...docs.map((d) => ({ lead: "•", leadWidth: 2, body: `${d.id}  ${labelBadge(d.labels, p)}` })),
	];
}

/** /hilfe: Befehle und wo das GO gefragt wird. */
export function hilfeRows(p: Paint): Row[] {
	return [
		{ body: p.bold("komki in pi") },
		...BEFEHLE.map(([b, was]) => ({ lead: p.fg("accent", b), leadWidth: 17, body: was })),
		{ body: "" },
		{ body: p.fg("muted", "Ist ein Aufruf gesperrt, fragt komki dein GO in einem eigenen Fenster, nie hier in pi.") },
	];
}
