defmodule KomkiCli.MixProject do
  use Mix.Project

  def project do
    [
      app: :komki_cli,
      version: "0.1.0",
      elixir: "~> 1.19",
      # test/support (Fixtures) nur in :test kompiliert — weder Escript (:dev)
      # noch Release sehen die Test-Helfer.
      elixirc_paths: elixirc_paths(Mix.env()),
      deps_path: "../artifacts/deps",
      lockfile: "../workspace.lock",
      start_permanent: Mix.env() == :prod,
      # Release-Bau (Ticket #75): Burrito-Wrap um ein mix release →
      # EINZELNE ausführbare Datei mit eingebettetem ERTS (kein Host-OTP nötig).
      releases: releases(),
      escript: [main_module: KomkiCli.CLI, name: "komki"],
      # dialyxir haelt diese App wegen lockfile "../workspace.lock" fuer ein
      # Umbrella-Child und versucht auf frischem Runner zuerst einen
      # Parent-PLT zu bauen. no_umbrella schaltet auf das normale
      # PLT-Verhalten dieser App um (Muster aus komki_policy).
      # ignore_warnings zeigt auf eine LEERE, committete Datei: es wird
      # nichts ignoriert — jede Warnung bleibt sichtbar und wird behoben;
      # die Angabe entfernt nur dialyxirs Hinweiszeile.
      dialyzer: [no_umbrella: true, ignore_warnings: "dialyzer.ignore-warnings"],
      deps: deps()
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  def application do
    [
      # :crypto (Steps.sha256, Pi-Profil-Hash) ist im Escript-Umfeld
      # unbemerkt vom Host-OTP gedeckt; Releases nehmen nur deklarierte
      # Apps ins Payload auf — ohne diesen Eintrag fehlt :crypto in der
      # Standalone-Binary (Ticket #75).
      extra_applications: [:logger, :crypto],
      # Release-Einstieg (Burrito): start/2 dispatcht CLI.main/1 und haelt
      # die VM mit dem Exit-Code an. Im Mix-Kontext (dev/test) No-Op.
      mod: {KomkiCli.Application, []}
    ]
  end

  # Release-/Burrito-Konfiguration (Ticket #75): wrappt das mix release in
  # eine selbstentpackende Einzeldatei (Zig-Wrapper; Entpacken beim ersten
  # Lauf nach ~/Library/Application Support/.burrito/).
  #
  # Bau:   MIX_ENV=prod BURRITO_TARGET=macos_silicon mix release
  # Output: burrito_out/komki_macos_silicon (eine Datei, enthaelt ERTS)
  #
  # Build-Voraussetzungen (docs/prerequisites.md): zig EXAKT 0.16.0
  # (Burrito prueft die Version auf Gleichheit) und xz im PATH; 7z nur fuer
  # Windows-Ziele (hier unbenutzt). MIX_ENV=prod ist Pflicht: nur prod-Builds
  # nutzen das einmal entpackte Payload wieder (dev re-extrahiert je Lauf).
  defp releases do
    [
      komki: [
        steps: [:assemble, &Burrito.wrap/1],
        burrito: [
          targets: [
            macos_silicon: [os: :darwin, cpu: :aarch64]
          ],
          debug: Mix.env() != :prod
        ]
      ]
    ]
  end

  # Runtime-Deps: optimus 0.6 (CLI-Layer), burrito 1.6 (Ticket #75),
  # exqlite 0.42 (SQLite-Registry des Label-Store, Ticket #91; direkt ohne
  # Ecto via Exqlite.Sqlite3) und komki_policy (Γ-Validierung bei Import und
  # Export: die Engine-Vertragsform `komki-registry/1` ist die alleinige
  # Schemainstanz, siehe apps/komki_policy/CONTRACT.md § 2.1). Path-Dep auf
  # die Workspace-Schwester ohne Hex-Lock-Eintrag.
  # :burrito ist bewusst RUNTIME — der dokumentierte Burrito-argv-Aufruf
  # (KomkiCli.Runtime.argv/0 → Burrito.Util.Args.argv/0) laeuft im Payload;
  # runtime:false wuerde ihn in der Standalone-Binary brechen. Benannter
  # Payload-Zusatz laut Ticket #75: Teile von :burrito landen in der
  # verteilten Binary (Dokumentation: docs/research/, README). Fuer
  # Gate-Ticket #91 gilt dasselbe fuer :exqlite (NIF) und :komki_policy.
  # Build-Werkzeuge (credo/dialyxir) nur :dev, runtime false.
  defp deps do
    [
      {:optimus, "~> 0.6"},
      {:burrito, "~> 1.6"},
      {:exqlite, "~> 0.42"},
      {:komki_policy, path: "../komki_policy"},
      {:credo, "~> 1.7", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: :dev, runtime: false}
    ]
  end
end
