// Tests für Raum, Labels und Raumdokumente in pi (priv/pi/komki-anzeige/raum.ts).
// Lauf: node --test apps/komki_cli/test/pi/
//
// Die Raumbilder haben die Form, die KomkiCli.Raumbild schreibt
// (raumbild_test.exs prüft die Elixir-Seite gegen dieselbe Form).

import assert from "node:assert/strict";
import { test } from "node:test";
import { dokumenteRows, draussen, headerRows, hilfeRows, parseRaum, raumRows, statusText } from "../../priv/pi/komki-anzeige/raum.ts";
import { layout, type Paint, type Row } from "../../priv/pi/komki-anzeige/view.ts";

const paint: Paint = {
	fg: (token, text) => `<${token}>${text}</>`,
	bold: (text) => `<b>${text}</>`,
};
const strip = (s: string) => s.replace(/<[^>]*>/g, "");
const text = (rows: Row[]) =>
	strip(
		layout(
			rows,
			200,
			(t) => [t],
			(s) => [...strip(s)].length,
		).join("\n"),
	);

const recherche = JSON.stringify({
	schema: "komki-raum/1",
	raum: "recherche",
	zweck: "offene-recherche",
	labels: [
		{ id: "doc-oeffentlich@2", bezeichnung: "Öffentliches Raumdokument", intern: false },
		{ id: "ris-oeffentlich@1", bezeichnung: "Öffentliche RIS-Inhalte", intern: false },
		{ id: "web-oeffentlich@1", bezeichnung: "Öffentliche Web-Treffer", intern: false },
	],
	nach_draussen: [
		{ empfaenger: "brave-search", offen: true },
		{ empfaenger: "ris-betreiber", offen: true },
	],
});

const vertraulich = JSON.stringify({
	schema: "komki-raum/1",
	raum: "vertraulich",
	zweck: "offene-recherche",
	labels: [
		{ id: "ris-oeffentlich@1", bezeichnung: "Öffentliche RIS-Inhalte", intern: false },
		{ id: "vault-vertraulich@1", bezeichnung: "Vertrauliche Vault-Notiz", intern: true },
	],
	nach_draussen: [
		{ empfaenger: "brave-search", offen: false },
		{ empfaenger: "ris-betreiber", offen: false },
	],
});

test("Raumbild lesen: falsche Form oder kaputtes JSON ergibt undefined", () => {
	assert.equal(parseRaum(undefined), undefined);
	assert.equal(parseRaum("kein json"), undefined);
	assert.equal(parseRaum('{"schema":"anders"}'), undefined);
	assert.equal(parseRaum(recherche)?.raum, "recherche");
});

test("Weg nach draußen in einem Satz", () => {
	assert.deepEqual(draussen(parseRaum(recherche)!), { offen: true, satz: "offen für Websuche und RIS" });
	assert.deepEqual(draussen(parseRaum(vertraulich)!), {
		offen: false,
		satz: "gesperrt, einzelne Aufrufe nur mit deinem GO im komki-Fenster",
	});
	const teils = parseRaum(recherche)!;
	teils.nach_draussen[0].offen = false;
	assert.match(draussen(teils)!.satz, /^offen für RIS; Websuche gesperrt, einzelne Aufrufe nur mit deinem GO/);
});

test("Kopfzeile: deutsch, Raum, Zweck, Labels in Worten, Befehle", () => {
	const out = text(headerRows(parseRaum(vertraulich), paint));
	assert.match(out, /^komki +Arbeitsraum für die Ratsarbeit$/m);
	assert.match(out, /^Raum vertraulich · Zweck: offene Recherche$/m);
	assert.match(out, /Labels +öffentlich, vertraulich/);
	assert.match(out, /Draußen +gesperrt, einzelne Aufrufe nur mit deinem GO im komki-Fenster/);
	assert.match(out, /Befehle +\/sitzungsmappe \/zusammenfassen \/quellen \/raum \/dokumente \/hilfe/);
	assert.doesNotMatch(out, /@\d/);
	assert.match(text(headerRows(undefined, paint)), /Das Raumbild fehlt/);
});

test("Fußzeile: Raum, Weg nach draußen, Anzahl der Raumdokumente", () => {
	assert.equal(statusText(parseRaum(recherche), undefined), "Raum recherche · nach draußen offen");
	assert.equal(statusText(parseRaum(vertraulich), []), "Raum vertraulich · nach draußen nur mit GO · 0 Raumdokumente");
	assert.equal(
		statusText(parseRaum(recherche), [{ id: "doc-oeffentlich", labels: ["doc-oeffentlich@2"] }]),
		"Raum recherche · nach draußen offen · 1 Raumdokument",
	);
	assert.equal(statusText(undefined, undefined), "eigener Raum");
});

test("/raum nennt Bezeichnungen und wer vertrauliche Labels sehen darf", () => {
	const out = text(raumRows(parseRaum(vertraulich), paint));
	assert.match(out, /Label +öffentlich {2}Öffentliche RIS-Inhalte/);
	assert.match(out, /Label +vertraulich {2}Vertrauliche Vault-Notiz · nur du und pi/);
	assert.match(out, /entscheidet der Vermittler bei jedem Aufruf/);
});

test("/dokumente: vor list_documents ein Hinweis, danach die Liste", () => {
	assert.match(text(dokumenteRows(undefined, paint)), /noch nicht aufgelistet/);
	assert.match(text(dokumenteRows([], paint)), /kein Dokument, das pi lesen kann/);
	const out = text(dokumenteRows([{ id: "doc-oeffentlich", labels: ["doc-oeffentlich@2"] }], paint));
	assert.match(out, /1 Raumdokument\n• doc-oeffentlich +öffentlich/);
});

test("nichts sieht wie eine Frage aus, die man in pi beantwortet", () => {
	const all = [
		headerRows(parseRaum(recherche), paint),
		headerRows(parseRaum(vertraulich), paint),
		raumRows(parseRaum(vertraulich), paint),
		dokumenteRows(undefined, paint),
		hilfeRows(paint),
	].map(text);
	for (const out of all) assert.doesNotMatch(out, /\[j\/N\]|\(j\/n\)|\?\s*$/m);
	assert.match(text(hilfeRows(paint)), /fragt komki dein GO in einem eigenen Fenster, nie hier in pi/);
});
