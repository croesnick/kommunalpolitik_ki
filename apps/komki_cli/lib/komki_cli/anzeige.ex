defmodule KomkiCli.Anzeige do
  @moduledoc """
  pi-Extension `komki-anzeige`: zeichnet die Tool-Aufrufe des Vermittlers in
  der Session lesbar statt als Roh-JSON (Quelle: `priv/pi/komki-anzeige/`,
  zur Compile-Zeit eingebettet). Sie registriert nur Renderer und ändert
  weder Entscheidungen noch den Modellkontext.

  Die Dateien liegen unter `<pi-home>/.pi/agent/komki-anzeige/` und werden wie
  das Relay vor jedem pi-Start neu geschrieben: Das pi-Home ist für den
  Agenten schreibbar, und eine veränderte Anzeige könnte eine Ablehnung als
  Zulassung zeigen.
  """

  alias KomkiCli.Config

  @source_dir Path.expand("../../priv/pi/komki-anzeige", __DIR__)
  @files for name <- ~w(index.ts view.ts),
             path = Path.join(@source_dir, name),
             do: {name, File.read!(path)}
  for {name, _} <- @files, do: @external_resource(Path.join(@source_dir, name))

  @spec dir(Config.t()) :: String.t()
  def dir(%Config{} = cfg), do: Path.join([cfg.pi_home, ".pi", "agent", "komki-anzeige"])

  @doc "Einstieg für `pi -e`."
  @spec entry(Config.t()) :: String.t()
  def entry(%Config{} = cfg), do: Path.join(dir(cfg), "index.ts")

  @doc "Schreibt die Extension frisch ins pi-Home; fremde Dateien im Ordner verschwinden."
  @spec write!(Config.t()) :: :ok
  def write!(%Config{} = cfg) do
    path = dir(cfg)
    File.rm_rf!(path)
    File.mkdir_p!(path)
    Enum.each(@files, fn {name, content} -> File.write!(Path.join(path, name), content) end)
  end

  @doc "Eingebettete Dateien (für Tests)."
  @spec files() :: [{String.t(), String.t()}]
  def files, do: @files
end
