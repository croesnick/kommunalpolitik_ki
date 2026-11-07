defmodule SealedEnvelope.MixProject do
  use Mix.Project

  def project do
    [
      app: :sealed_envelope,
      version: "0.1.0",
      elixir: "~> 1.19",
      deps_path: "../artifacts/deps",
      lockfile: "../workspace.lock",
      start_permanent: Mix.env() == :prod,
      # Pattern from sidecar: without this dialyxir treats the app as an
      # umbrella child; the ignore file is empty (nothing is ignored).
      dialyzer: [no_umbrella: true, ignore_warnings: "dialyzer.ignore-warnings"],
      deps: deps()
    ]
  end

  # Library without an application callback: the envelope format, the
  # key-agreement behaviour and a file-backed test double. No runtime deps —
  # ECDH, HMAC and AES-GCM come from OTP's :crypto, JSON from Elixir.
  def application do
    [extra_applications: [:crypto]]
  end

  defp deps do
    [
      {:credo, "~> 1.7", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: :dev, runtime: false}
    ]
  end
end
