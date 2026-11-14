defmodule KomkiConnectorVault.MixProject do
  use Mix.Project

  def project do
    [
      app: :komki_connector_vault,
      version: "0.1.0",
      elixir: "~> 1.19",
      deps_path: "../artifacts/deps",
      lockfile: "../workspace.lock",
      start_permanent: Mix.env() == :prod,
      escript: [main_module: KomkiConnectorVault.CLI, name: "komki-connector-vault"],
      # Muster aus komki_connector: dialyxir haelt die App sonst fuer ein
      # Umbrella-Child; die ignore-Datei ist leer (nichts wird ignoriert).
      dialyzer: [no_umbrella: true, ignore_warnings: "dialyzer.ignore-warnings"],
      deps: deps()
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  # Einzige Runtime-Dep: die eingefrorene Connector-Bibliothek (Frame,
  # Server, Manifest). Kein YAML-Parser — das Frontmatter liest ein
  # minimaler eigener Parser (KomkiConnectorVault.Note).
  defp deps do
    [
      {:komki_connector, path: "../komki_connector"},
      {:sidecar, path: "../sidecar"},
      {:credo, "~> 1.7", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: :dev, runtime: false}
    ]
  end
end
