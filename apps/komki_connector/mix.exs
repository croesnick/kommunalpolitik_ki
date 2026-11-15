defmodule KomkiConnector.MixProject do
  use Mix.Project

  def project do
    [
      app: :komki_connector,
      version: "0.1.0",
      description:
        "Komki-Seite des Connector-Vertrags: Manifeste, deutsche Modell-Texte, Start-Einstieg und CA-Zertifikate",
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
  # Manifeste. Keine Hex-Dep — JSON kommt aus OTP (:json, OTP 27+); die
  # Workspace-Schwester seatbelt liefert die Pfad-Kanonisierung für die
  # zweite Programmform (KomkiConnector.Nif, #288).
  def application do
    [extra_applications: [:logger, :crypto, :public_key]]
  end

  defp deps do
    [
      {:sidecar, path: "../sidecar"},
      {:seatbelt, path: "../seatbelt"},
      {:credo, "~> 1.7", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: :dev, runtime: false}
    ]
  end
end
