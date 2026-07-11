defmodule KommunalpolitikKi.MixProject do
  use Mix.Project

  def project do
    [
      app: :kommunalpolitik_ki,
      version: "0.1.0",
      elixir: "~> 1.19",
      elixirc_paths: [],
      deps_path: "artifacts/deps",
      lockfile: "workspace.lock",
      deps: deps(),
      workspace: [type: :workspace]
    ]
  end

  def application, do: []

  defp deps do
    [
      {:workspace, "~> 0.2", only: :dev}
    ]
  end
end
