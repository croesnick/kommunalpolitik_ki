defmodule KomkiConnectorWeb.MixProject do
  use Mix.Project

  def project do
    [
      app: :komki_connector_web,
      version: "0.1.0",
      elixir: "~> 1.19",
      deps_path: "../artifacts/deps",
      lockfile: "../workspace.lock",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      escript: [main_module: KomkiConnectorWeb.CLI, name: "komki-connector-web"],
      # Muster aus komki_mediator: dialyxir haelt die App sonst fuer ein
      # Umbrella-Child; die ignore-Datei ist leer (nichts wird ignoriert).
      dialyzer: [
        no_umbrella: true,
        ignore_warnings: "dialyzer.ignore-warnings",
        plt_add_apps: [:inets, :ssl, :public_key]
      ],
      deps: deps()
    ]
  end

  # HTTP ueber :httpc (inets), TLS ueber :ssl — beides OTP, keine Hex-Deps.
  def application do
    [extra_applications: [:logger, :crypto, :inets, :ssl, :public_key]]
  end

  # Mock-HTTP-Server fuer die Tests.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:komki_connector, path: "../komki_connector"},
      {:credo, "~> 1.7", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: :dev, runtime: false}
    ]
  end
end
