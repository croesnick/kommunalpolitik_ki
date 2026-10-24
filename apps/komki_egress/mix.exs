defmodule KomkiEgress.MixProject do
  use Mix.Project

  def project do
    [
      app: :komki_egress,
      version: "0.1.0",
      elixir: "~> 1.19",
      deps_path: "../artifacts/deps",
      lockfile: "../workspace.lock",
      start_permanent: Mix.env() == :prod,
      escript: [main_module: KomkiEgress.CLI, name: "komki-egress"],
      # Muster aus komki_mediator: dialyxir haelt die App sonst fuer ein
      # Umbrella-Child; die ignore-Datei ist leer (nichts wird ignoriert).
      dialyzer: [no_umbrella: true, ignore_warnings: "dialyzer.ignore-warnings"],
      deps: deps()
    ]
  end

  # Keine Runtime-Deps: Sockets, DNS und JSON kommen aus OTP bzw. Elixir.
  def application do
    [extra_applications: [:logger]]
  end

  defp deps do
    [
      {:credo, "~> 1.7", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: :dev, runtime: false}
    ]
  end
end
