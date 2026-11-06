defmodule KomkiMock.MixProject do
  use Mix.Project

  def project do
    [
      app: :komki_mock,
      version: "0.1.0",
      elixir: "~> 1.19",
      deps_path: "../artifacts/deps",
      lockfile: "../workspace.lock",
      start_permanent: Mix.env() == :prod,
      # Pattern from sidecar: without no_umbrella dialyxir treats the app as
      # an umbrella child; the ignore file is empty (nothing is ignored).
      # :mix for the serve task.
      dialyzer: [
        no_umbrella: true,
        ignore_warnings: "dialyzer.ignore-warnings",
        plt_add_apps: [:mix]
      ],
      deps: deps()
    ]
  end

  # Not part of the Homebrew release: the mock world exists for tests and
  # agents only. :inets is only used by the tests (httpc).
  def application do
    [extra_applications: [:logger, :inets]]
  end

  defp deps do
    [
      {:bandit, "~> 1.12"},
      {:credo, "~> 1.7", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: :dev, runtime: false}
    ]
  end
end
