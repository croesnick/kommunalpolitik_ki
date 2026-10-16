defmodule KomkiMediator.MixProject do
  use Mix.Project

  def project do
    [
      app: :komki_mediator,
      version: "0.1.0",
      elixir: "~> 1.19",
      deps_path: "../artifacts/deps",
      lockfile: "../workspace.lock",
      # test/support (Helfer) nur in :test kompiliert — Escript (:dev)
      # und Release sehen die Test-Helfer nicht (Muster aus komki_policy).
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      escript: [main_module: KomkiMediator.CLI, name: "komki-mediator"],
      # dialyxir haelt diese App wegen lockfile "../workspace.lock" fuer ein
      # Umbrella-Child und versucht auf frischem Runner zuerst einen
      # Parent-PLT zu bauen. no_umbrella schaltet auf das normale
      # PLT-Verhalten dieser App um (Muster aus komki_policy/komki_cli).
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
      # :crypto (sha256-Pruefwerke, starke Zufalls-IDs) und :ssl (:inets-httpc
      # nur in Tests) sind im Escript-Umfeld unbemerkt vom Host-OTP gedeckt.
      extra_applications: [:logger, :crypto]
    ]
  end

  # Runtime-Deps:
  # - komki_policy: der Policy-Kern (Derive.decide, Verify.check, JSON) —
  #   Pflicht-Gate fuer jeden Toolaufruf (Tor 1/Tor 2).
  # - anubis_mcp: MCP-Server-Layer (StreamableHTTP-Transport, Plug).
  # - bandit: HTTP-Listener, nur loopback. Der Escript nimmt Runtime-Deps
  #   automatisch ins Payload auf (Praezedenz: komki_cli mit optimus/burrito).
  # Build-Werkzeuge (credo/dialyxir) nur :dev, runtime false.
  defp deps do
    [
      {:komki_policy, path: "../komki_policy"},
      {:anubis_mcp, "~> 1.6"},
      {:bandit, "~> 1.12"},
      {:credo, "~> 1.7", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: :dev, runtime: false}
    ]
  end
end
