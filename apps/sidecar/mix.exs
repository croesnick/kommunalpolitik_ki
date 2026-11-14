defmodule Sidecar.MixProject do
  use Mix.Project

  def project do
    [
      app: :sidecar,
      version: "0.1.0",
      elixir: "~> 1.19",
      deps_path: "../artifacts/deps",
      lockfile: "../workspace.lock",
      start_permanent: Mix.env() == :prod,
      # Pattern from komki_mediator: without this dialyxir treats the app as
      # an umbrella child; the ignore file is empty (nothing is ignored).
      dialyzer: [no_umbrella: true, ignore_warnings: "dialyzer.ignore-warnings"],
      deps: deps()
    ]
  end

  # Library without an application callback: the frame protocol, the
  # capability token, parameter validation, the caller-side client and the
  # sidecar server. No runtime deps — JSON comes from OTP (:json, OTP 27+).
  def application do
    [extra_applications: [:logger, :crypto]]
  end

  defp deps do
    [
      {:credo, "~> 1.7", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: :dev, runtime: false}
    ]
  end
end
