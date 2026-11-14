defmodule KomkiConnectorDocuments.MixProject do
  use Mix.Project

  def project do
    [
      app: :komki_connector_documents,
      version: "0.1.0",
      elixir: "~> 1.19",
      # test/support (TestPDF factory) is compiled in :test only.
      elixirc_paths: elixirc_paths(Mix.env()),
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

  defp elixirc_paths(:test), do: ["lib", "test/support"]

  defp elixirc_paths(_), do: ["lib"]

  # Runtime deps: the connector library (frame, server, manifest) and
  # ex_pdfium for PDFs (#290; NIF origin in KomkiConnectorDocuments.Pdf).
  defp deps do
    [
      {:komki_connector, path: "../komki_connector"},
      {:sidecar, path: "../sidecar"},
      {:ex_pdfium, "~> 0.7.0"},
      {:credo, "~> 1.7", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: :dev, runtime: false}
    ]
  end
end
