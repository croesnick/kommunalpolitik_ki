---
komki: major
---

# Eine Suche aus einem vertraulichen Raum ist eine Offenlegung, kein gewöhnliches GO

Fragt pi aus einem Raum mit vertraulicher Bindung im Web oder im RIS, fragt dich
das Freigabefenster jetzt nach einer Offenlegung: Es nennt die Bindung, die dein GO
aufhebt, und fragt „Ich gebe genau diese Anfrage bewusst an … weiter.“ In den
Räumen `vertraulich`, `projektraum` und `fraktion` geht das wie bisher für genau
eine Anfrage. Liegt im Raum etwas, das du dafür nicht lockern darfst, etwa
nichtöffentliche Ratsunterlagen, erscheint kein Fenster, und pi erfährt nur, dass
nichts übertragen wurde. Bei der Essenz in den Hub hebt eine Offenlegung nur noch
die Bindungen auf, die der Hub nicht lesen darf; das Journal hält das Ziellabel
fest. Ein bestehender Label-Store startet ohne Handgriff weiter: `komki up`
ersetzt die vier betroffenen mitgelieferten Bindungen in ihrer früheren Fassung,
nennt das in je einer Zeile und hält es im Store fest.
