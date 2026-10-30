---
id: kurzprompt-top3
typ: verhalten
beschreibung: >
  Regressionsfall aus #158: derselbe TOP unter knappem Prompt
  (»höchstens fünf Sätze«). Ohne Skill fehlte der Eigenanteil in jedem
  Lauf; das Kriterium hier verlangt die Zahl, das Wort »Eigenanteil«
  allein genügt nicht (Lehre aus #158: ein zu lasches K6 machte aus
  2/5 versehentlich 5/5).
arme: [ohne-skill, vorige, aktuelle]
tools: read
timeout_s: 300
laeufe: 5
quelle: "#158, Aufgabe 1 und TOP-Benchmark (run-top-bench.mjs, K1–K8)"
---

Lies die Datei top-3-anhoerung.md im aktuellen Verzeichnis und fasse TOP 3 für die Sitzungsvorbereitung in höchstens fünf Sätzen zusammen. Nenne Gremium, Sitzungsdatum, Kostenschätzung und Beschlussvorschlag.
