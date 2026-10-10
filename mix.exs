defmodule KommunalpolitikKi.MixProject do
  use Mix.Project

  def project do
    [
      app: :kommunalpolitik_ki,
      version: "0.1.0",
      elixir: "~> 1.19",
      elixirc_paths: [],
      deps_path: "artifacts/deps",
      lockfile: "workspace.lock",
      deps: deps(),
      aliases: aliases(),
      workspace: [type: :workspace]
    ]
  end

  def application, do: []

  # DevX: dialyzer ist app-lokal (dialyxir missdeutet jede Workspace-App als
  # Umbrella-Child; der Root-Dispatch crasht). Ohne dieses Alias kam der
  # Fehler erst im Lauf ("task could not be found") — jetzt bricht der Aufruf
  # sofort mit der richtigen Invocation ab.
  defp aliases do
    [
      dialyzer: fn _args ->
        Mix.raise("""
        mix dialyzer laeuft app-lokal (Workspace-Pattern):

            cd apps/<app> && mix dialyzer

        Der Root-Dispatch crasht (dialyxir-Umbrella-Fehldeutung).
        """)
      end
    ]
  end

  defp deps do
    [
      {:workspace, "~> 0.3", only: :dev}
    ]
  end
end
