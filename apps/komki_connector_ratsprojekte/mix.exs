defmodule KomkiConnectorRatsprojekte.MixProject do
  use Mix.Project

  def project do
    [
      app: :komki_connector_ratsprojekte,
      version: "0.1.0",
      elixir: "~> 1.19",
      deps_path: "../artifacts/deps",
      lockfile: "../workspace.lock",
      start_permanent: Mix.env() == :prod,
      # Muster aus komki_connector: dialyxir haelt die App sonst fuer ein
      # Umbrella-Child; die ignore-Datei ist leer (nichts wird ignoriert).
      dialyzer: [no_umbrella: true, ignore_warnings: "dialyzer.ignore-warnings"],
      deps: deps()
    ]
  end

  def application do
    [extra_applications: [:logger, :crypto]]
  end

  # DURCHSTICH #409 (Wegwerf): Connector-Rolle fuer den ratsprojekte-Hub.
  # Kein eigenes Escript — der Start laeuft als Multicall-Rolle des
  # komki-Programms (KomkiCli.Roles). Das HTTP zum Hub ist handgestrickt
  # ueber :gen_tcp, damit keine neue Abhaengigkeit entsteht (GO-Regel,
  # AGENTS.md §1).
  defp deps do
    [
      {:komki_connector, path: "../komki_connector"},
      {:komki_policy, path: "../komki_policy"},
      {:sidecar, path: "../sidecar"},
      # Nur :dev wie die Schwester-Apps: der Workspace-Credo-Lauf des Pre-Commit-Hooks
      # erwartet die Task in jeder App (DURCHSTICH #409).
      {:credo, "~> 1.7", only: :dev, runtime: false}
    ]
  end
end
