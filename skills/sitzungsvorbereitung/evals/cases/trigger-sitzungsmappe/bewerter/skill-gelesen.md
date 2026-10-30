---
id: skill-gelesen
typ: tool-call
tool: read
parameter: "sitzungsvorbereitung/SKILL\.md"
anzahl_min: 1
---

Das Kernkriterium des Trigger-Falls: pi annonciert alle Skills im
System-Prompt (<available_skills> mit Name, Description, Pfad) und das
Modell muss die SKILL.md des passenden Skills selbst per read laden.
Kommt dieser Aufruf nicht, greift die Description nicht.
