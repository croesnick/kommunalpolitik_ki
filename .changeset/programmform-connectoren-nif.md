---
komki: minor
---

# PDFs lesen im Escript-Betrieb: Der Dokument-Connector lädt pdfium von der Platte

Bisher scheiterte jede PDF-Lesung im Escript-Betrieb (`make komki`, Homebrew-Paket), weil der
native Baustein (pdfium) aus dem gezippten Programm-Archiv nicht laden kann; nur die
Burrito-Einzeldatei konnte PDFs lesen. Der Dokument-Connector läuft jetzt in der zweiten
Programmform (Entscheidung zu #288): Er lädt ex_pdfium und libpdfium aus dem Verzeichnis
neben dem Programm — aus dem Build-Baum oder aus `lib/` im Paket —, so wie komki selbst die
SQLite-Bibliothek lädt. PDF-Raumdokumente lassen sich damit im normalen Betrieb lesen.

Dazu passt sich die Sicherheitskette an: Das Connector-Profil erlaubt das Laden nur aus
genau diesem Verzeichnis, die nativen Dateien stehen als eigener Programm-Pin
(`pin komki-connector-documents-nif`, Baum-Hash), und `komki doctor` lädt den Baustein bei
jedem Lauf wirklich — unter dem Profil der Instanz, nicht nur als Ping. Fehlt das
Verzeichnis, etwa nach einem Update ohne `komki setup`, meldet der Doctor `nif documents`
rot, und `komki up` startet erst nach `komki setup`.
