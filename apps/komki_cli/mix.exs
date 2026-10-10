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
      extra_applications: [:logger]
    ]
  end

  # Runtime-Deps: genau eine — optimus 0.6 (CLI-Layer, Nutzer-Entscheidung zum
  # Retrofit; in apps/ratsinfo als escript-Precedent bewiesene Version). Alle
  # Restmodule (Profile/Llama/Pi/Config) bleiben ohne Runtime-Deps. Build-Werkzeuge
  # (credo/dialyxir) nur :dev, runtime false.
  defp deps do
    [
      {:optimus, "~> 0.6"},
      {:credo, "~> 1.7", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: :dev, runtime: false}
    ]
  end
end
