---
komki: major
---

# Eine Suche aus einem vertraulichen Raum ist eine Offenlegung, kein gewöhnliches GO

Fragt pi aus einem Raum mit vertraulicher Bindung im Web oder im RIS, öffnet das
Freigabefenster jetzt eine Offenlegung: Es nennt die Bindung, die dein GO aufhebt,
und fragt „Ich gebe genau diesen Suchtext bewusst an … weiter.“ In den Räumen
`vertraulich`, `projektraum` und `fraktion` geht das wie bisher für genau einen
Suchtext. Liegt im Raum etwas, das du dafür nicht lockern darfst, etwa
nichtöffentliche Ratsunterlagen, erscheint kein Fenster mehr, und pi erfährt nur,
dass nichts übertragen wurde. Bei der Essenz in den Hub bleiben öffentliche
Bindungen am Text, statt still wegzufallen. Ein bestehender Label-Store startet
ohne Handgriff weiter: `komki up` ersetzt die vier betroffenen mitgelieferten
Bindungen in ihrer früheren Fassung und hält das im Store fest.
