defmodule WegwerfHub.MixProject do
  use Mix.Project

  def project do
    [
      app: :wegwerf_hub,
      version: "0.1.0",
      elixir: "~> 1.19",
      deps_path: "../artifacts/deps",
      lockfile: "../workspace.lock",
      start_permanent: Mix.env() == :prod,
      escript: [main_module: WegwerfHub.CLI, name: "wegwerf-hub"],
      dialyzer: [no_umbrella: true, ignore_warnings: "dialyzer.ignore-warnings"],
      deps: deps()
    ]
  end

  def application do
    [extra_applications: [:logger, :crypto]]
  end

  # DURCHSTICH #409 (Wegwerf, nie gemergt): Der Wegwerf-Hub ist der
  # Platzhalter fuer den echten ratsprojekte-Hub (#414 entscheidet Modell
  # und Oberflaeche): Bandit auf einem Unix-Socket, nur die
  # Connector-Operation, Token nur als Hash (#415). Dazu der Durchstich-
  # Runner (WegwerfHub.Durchstich), der die Szenen 11.x als geskriptete
  # Aufrufe gegen den echten Vermittler faehrt.
  defp deps do
    [
      {:bandit, "~> 1.0"},
      {:plug, "~> 1.0"},
      {:komki_mediator, path: "../komki_mediator"},
      {:komki_policy, path: "../komki_policy"},
      # Nur :dev wie die Schwester-Apps: der Workspace-Credo-Lauf des Pre-Commit-Hooks
      # erwartet die Task in jeder App (DURCHSTICH #409).
      {:credo, "~> 1.7", only: :dev, runtime: false}
    ]
  end
end
