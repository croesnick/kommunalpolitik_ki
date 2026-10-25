# croesnick/tap

Homebrew-Tap für komki, den lokalen KI-Arbeitsraum für die Ratsarbeit
([Doku](https://croesnick.github.io/kommunalpolitik_ki/)).

Dieser Tap ist zurzeit rein lokal: `make komki-tap` im Repo
[croesnick/kommunalpolitik_ki](https://github.com/croesnick/kommunalpolitik_ki)
baut das Paket, schreibt `Formula/komki.rb` mit einer `file://`-Adresse
hierher, committet und installiert neu. Die Vorlage der Formel liegt dort
unter `packaging/homebrew/komki.rb.in`.

```sh
brew install croesnick/tap/komki   # vertraut nur dieser Formel (Tap Trust)
komki setup
```

Nach einem Upgrade einmal `komki setup` ausführen: Es frischt Programmpfade
und Sandbox-Profile auf, Einstellungen bleiben.
