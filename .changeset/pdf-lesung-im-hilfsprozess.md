---
komki: patch
---

# PDF-Lesung läuft in einem eigenen Hilfsprozess

Der Dokument-Connector liest PDFs nicht mehr in seinem eigenen VM: Ein
zweiter Betriebssystemprozess — derselbe BEAM, dasselbe Seatbelt-Profil —
lädt das PDFium-NIF. Stirbt der Hilfsprozess durch einen Crash, durch
Speicherdruck oder wenn er das Zeitbudget von 12 Sekunden überschreitet,
antwortet der Connector genau diesen einen Aufruf mit `upstream-error` und
bleibt erreichbar. Vorher konnte eine einzige präparierte PDF-Datei (stark
expandierender Datenstrom) den Connector für die ganze Instanz blockieren
oder komplettlegen — nachgemessen: 1,8 MB Datei, 54 Sekunden Rechenzeit und
rund 32 GB Speicherbedarf in einer einzigen Anfrage.

Die Adresse-Raum-Begrenzung bleibt bewusst nur ein Versuch in der Aufrufzeile:
macOS weist `setrlimit` für RLIMIT_AS systemweit ab (gemessen), wirksam sind
hier Zeitbudget und Crash-Isolation. Eine Dekompressionsgrenze vor der
Materialisierung gehört in das externe Paket ex_pdfium und bleibt offen
(Ticket #488).
