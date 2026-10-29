defmodule KomkiConnectorRis.MixProject do
  use Mix.Project

  def project do
    [
      app: :komki_connector_ris,
      version: "0.1.0",
      elixir: "~> 1.19",
      deps_path: "../artifacts/deps",
      lockfile: "../workspace.lock",
      start_permanent: Mix.env() == :prod,
      escript: [main_module: KomkiConnectorRis.CLI, name: "komki-connector-ris"],
      # Muster aus komki_connector: dialyxir haelt die App sonst fuer ein
      # Umbrella-Child; die ignore-Datei ist leer (nichts wird ignoriert).
      dialyzer: [
        no_umbrella: true,
        ignore_warnings: "dialyzer.ignore-warnings",
        plt_add_apps: [:inets, :ssl, :public_key]
      ],
      deps: deps()
    ]
  end

  # HTTP ueber :httpc (inets) mit TLS aus :ssl/:public_key — keine
  # Runtime-Deps ausser der Connector-Bibliothek.
  def application do
    [extra_applications: [:logger, :inets, :ssl, :public_key]]
  end

  defp deps do
    [
      {:komki_connector, path: "../komki_connector"},
      {:sidecar, path: "../sidecar"},
      {:credo, "~> 1.7", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: :dev, runtime: false}
    ]
  end
end
