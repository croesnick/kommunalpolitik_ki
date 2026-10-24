defmodule KomkiConnector.MixProject do
  use Mix.Project

  def project do
    [
      app: :komki_connector,
      version: "0.1.0",
      elixir: "~> 1.19",
      deps_path: "../artifacts/deps",
      lockfile: "../workspace.lock",
      start_permanent: Mix.env() == :prod,
      # Muster aus komki_mediator: dialyxir haelt die App sonst fuer ein
      # Umbrella-Child; die ignore-Datei ist leer (nichts wird ignoriert).
      dialyzer: [no_umbrella: true, ignore_warnings: "dialyzer.ignore-warnings"],
      deps: deps()
    ]
  end

  # Bibliothek ohne Application-Callback: Frame-Protokoll, Client, Server und
  # Manifeste. Keine Runtime-Deps — JSON kommt aus OTP (:json, OTP 27+).
  def application do
    [extra_applications: [:logger, :crypto, :public_key]]
  end

  defp deps do
    [
      {:credo, "~> 1.7", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: :dev, runtime: false}
    ]
  end
end
