defmodule KomkiPolicy.MixProject do
  use Mix.Project

  def project do
    [
      app: :komki_policy,
      version: "0.1.0",
      elixir: "~> 1.19",
      deps_path: "../artifacts/deps",
      lockfile: "../workspace.lock",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      escript: [main_module: KomkiPolicy.CLI, name: "komki-policy"],
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Null Runtime-Deps (CONTRACT.md § 7): der Determinismus des Policy-Kerns
  # soll nicht von externen Hex-Versionen abhängen.
  #
  # counterpartige Build-Werkzeuge: nur :dev — `mix test` (Umgebung :test)
  # braucht sie daher nicht und `../workspace.lock` bleibt unverändert.
  defp deps do
    [
      {:credo, "~> 1.7", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: :dev, runtime: false}
    ]
  end
end
