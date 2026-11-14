---
komki: patch
---

# RIS: TOP-Texte ohne rohe HTML-Entities

`ris show` lieferte Textblöcke mit rohen Entities wie `W&uuml;rdigung`, `&sect; 246e BauGB`
oder `&bdquo;Gesetz …&ldquo;`, wenn das RIS mehr als die XML-Kern-Entities ausspielt — das
kostete Tokens und ließ Zitate vom Original abweichen (Quellenpflicht). Der Connector
dekodiert jetzt den Latin-1-Vorrat von HTML 4 und die Satz- und Währungszeichen deutscher
Gremientexte (Anführungszeichen, Gedankenstriche, Euro); unbekannte Entities bleiben roh
stehen. Neu dazu: `priv/ris_tagesordnung.exs` prüft die Tagesordnung eines Sitzungstags
gegen das echte RIS (eine Freigabe per Touch ID) und meldet „Texte mit ungelösten
HTML-Entities: N“.
