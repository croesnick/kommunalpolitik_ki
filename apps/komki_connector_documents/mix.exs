defmodule KomkiConnectorDocuments.MixProject do
  use Mix.Project

  def project do
    [
      app: :komki_connector_documents,
      version: "0.1.0",
      elixir: "~> 1.19",
      # test/support (TestPDF-Fabrik) nur in :test kompiliert.
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

  # Runtime-Deps: die Connector-Bibliothek (Frame, Server, Manifest) und
  # ex_pdfium fuer PDFs (Ticket #290; NIF siehe KomkiConnectorDocuments.Pdf).
  defp deps do
    [
      {:komki_connector, path: "../komki_connector"},
      {:sidecar, path: "../sidecar"},
      {:ex_pdfium, "~> 0.6"},
      {:credo, "~> 1.7", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: :dev, runtime: false}
    ]
  end
end
