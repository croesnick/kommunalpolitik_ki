---
id: foerderfrist
typ: llm
---

PASS wenn die Antwort einen terminlichen Bezug der Förderung nennt — z. B. den Zuwendungsbescheid vom 19.09.2026, einen Bewilligungs- oder Abrufzeitraum, eine Frist für den Mittelabruf — ODER ausdrücklich als Lücke benennt, dass die Vorlage keine Förderfrist (Mittelabruf, Bewilligungszeitraum) angibt.
FAIL wenn die Antwort zur Förderung keinen terminlichen Bezug herstellt und die fehlende Förderfrist auch nicht als Lücke benennt.
Hintergrund: Das Regex-Kriterium aus #158 (»Frist für den Abruf der Landesförderung«) war zu eng und warf Nennungen mit anderer Wortstellung weg; deshalb hier der Richter mit konkreter PASS-Bedingung statt eines strengeren Regex.
