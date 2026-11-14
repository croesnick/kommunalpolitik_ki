defmodule Seatbelt.MixProject do
  use Mix.Project

  def project do
    [
      app: :seatbelt,
      version: "0.1.0",
      elixir: "~> 1.19",
      deps_path: "../artifacts/deps",
      lockfile: "../workspace.lock",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      # Coverage floor for `mix test --cover` runs only; the load-bearing
      # quality gates are the byte-identity goldens, the determinism tests
      # and the pinned preset rule lines. Measured floor on a macOS dev
      # host is ~75 %; the otool walk and the sandbox-exec probes have
      # macOS-only happy paths, so Linux runs land lower — the floor
      # guards regressions without chasing the metric (komki_policy
      # precedent). Note: this mix version reads the threshold from
      # :summary; a top-level :threshold is ignored.
      test_coverage: [summary: [threshold: 70]],
      # dialyxir misreads this app as an umbrella child because of the
      # "../workspace.lock" lockfile and tries to bootstrap a parent PLT on a
      # fresh runner first (dialyxir dialyzer.ex:241-255); the root project
      # has no dialyxir dep, so that bootstrap crashes. no_umbrella switches
      # to normal PLT behavior (pattern from komki_policy).
      # ignore_warnings points at an EMPTY, committed file: nothing is
      # ignored — every warning stays visible and gets fixed; the entry only
      # removes dialyxir's hint line.
      dialyzer: [no_umbrella: true, ignore_warnings: "dialyzer.ignore-warnings"],
      deps: deps()
    ]
  end

  def application do
    [
      # :crypto is Erlang/OTP stdlib (SHA-256 in Seatbelt.Pins) — no hex
      # dependency, no change to deps.
      extra_applications: [:logger, :crypto]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Zero runtime deps: the byte-identity contract of the profile generators
  # must not depend on external hex versions (CONTRACT pattern from
  # komki_policy).
  #
  # Build tooling only: :dev — `mix test` (env :test) does not need it and
  # ../workspace.lock stays unchanged.
  defp deps do
    [
      {:credo, "~> 1.7", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: :dev, runtime: false}
    ]
  end
end
