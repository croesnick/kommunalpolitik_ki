defmodule KomkiConnectorDocuments.MixProject do
  use Mix.Project

  def project do
    [
      app: :komki_connector_documents,
      version: "0.1.0",
      elixir: "~> 1.19",
      deps_path: "../artifacts/deps",
      lockfile: "../workspace.lock",
      start_permanent: Mix.env() == :prod,
      escript: [main_module: KomkiConnectorDocuments.CLI, name: "komki-connector-documents"],
      # Muster aus komki_connector: dialyxir haelt die App sonst fuer ein
      # Umbrella-Child; die ignore-Datei ist leer (nichts wird ignoriert).
      dialyzer: [no_umbrella: true, ignore_warnings: "dialyzer.ignore-warnings"],
      deps: deps()
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  # Einzige Runtime-Dep: die Connector-Bibliothek (Frame, Server, Manifest).
  defp deps do
    [
      {:komki_connector, path: "../komki_connector"},
      {:credo, "~> 1.7", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: :dev, runtime: false}
    ]
  end
end
