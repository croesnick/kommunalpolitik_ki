---
komki: patch
---

# komki-policy: Offenlegungsfreigabe nur anbieten, wenn sie wirken kann

Eine abgelehnte Speicherung bekommt das Angebot einer Offenlegungsfreigabe jetzt nur noch, wenn das Ziellabel registriert ist und den Speicher lesen darf. Bisher erschien das Angebot auch dann, und eine danach erteilte Freigabe wurde wieder abgelehnt. Eine Offenlegungsfreigabe mit unbekanntem Ziellabel führt jetzt zu einer Ablehnung mit `ziellabel_unknown` statt zu einem Absturz von `komki-policy decide`.
