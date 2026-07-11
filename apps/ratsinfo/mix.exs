defmodule Ratsinfo.MixProject do
  use Mix.Project

  def project do
    [
      app: :ratsinfo,
      version: "0.1.0",
      elixir: "~> 1.20",
      deps_path: "../artifacts/deps",
      lockfile: "../workspace.lock",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
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

  defp deps do
    [
      {:shared, path: "../shared"},
      {:req, "~> 0.5"},
      {:floki, "~> 0.36"},
      {:exqlite, "~> 0.25"},
      {:optimus, "~> 0.6"},
      {:jason, "~> 1.4"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end
end
