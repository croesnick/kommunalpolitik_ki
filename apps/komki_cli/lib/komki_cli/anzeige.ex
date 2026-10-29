defmodule KomkiCli.Anzeige do
  @moduledoc """
  Oberfläche der pi-Session, die komki mitbringt (Quelle: `priv/pi/`, zur
  Compile-Zeit eingebettet):

    * `komki-anzeige/`: Extension, die die Tool-Aufrufe des Vermittlers
      lesbar statt als Roh-JSON zeichnet. Sie registriert nur Renderer und
      ändert weder Entscheidungen noch den Modellkontext.
    * `komki-vorlagen/`: Prompt-Vorlagen für die Ratsarbeit
      (`/sitzungsmappe`, `/zusammenfassen`, `/quellen`). Reiner Text, den
      die nutzende Person selbst abschickt; keine Befugnis.
    * `komki-themes/`: Farben wie die Doku-Site, hell und dunkel; pi wählt
      nach dem Terminal.

  Die Dateien liegen unter `<pi-home>/.pi/agent/` und werden wie das Relay
  vor jedem pi-Start neu geschrieben: Das pi-Home ist für den Agenten
  schreibbar. Eine veränderte Anzeige oder ein verändertes Theme könnte eine
  Ablehnung als Zulassung zeigen, eine veränderte Vorlage dem Modell fremde
  Anweisungen unterschieben.
  """

  alias KomkiCli.Config

  @priv Path.expand("../../priv/pi", __DIR__)
  @parts ~w(komki-anzeige komki-vorlagen komki-themes)
  @files for part <- @parts,
             name <- @priv |> Path.join(part) |> File.ls!() |> Enum.sort(),
             path = Path.join([@priv, part, name]),
             do: {Path.join(part, name), File.read!(path)}
  for {rel, _} <- @files, do: @external_resource(Path.join(@priv, rel))

  @themes "komki-hell/komki-dunkel"

  @spec dir(Config.t()) :: String.t()
  def dir(%Config{} = cfg), do: part_dir(cfg, "komki-anzeige")

  @doc "Einstieg für `pi -e`."
  @spec entry(Config.t()) :: String.t()
  def entry(%Config{} = cfg), do: Path.join(dir(cfg), "index.ts")

  @doc "pi-Flags der Session: Extension, Vorlagen, Themes (hell/dunkel nach Terminal)."
  @spec flags(Config.t()) :: [String.t()]
  def flags(%Config{} = cfg) do
    [
      "-e",
      entry(cfg),
      "--prompt-template",
      part_dir(cfg, "komki-vorlagen"),
      "--theme",
      part_dir(cfg, "komki-themes"),
      "--use-theme",
      @themes
    ]
  end

  @doc "Schreibt alle Teile frisch ins pi-Home; fremde Dateien in den Ordnern verschwinden."
  @spec write!(Config.t()) :: :ok
  def write!(%Config{} = cfg) do
    for part <- @parts do
      path = part_dir(cfg, part)
      File.rm_rf!(path)
      File.mkdir_p!(path)
    end

    Enum.each(@files, fn {rel, content} ->
      File.write!(Path.join([cfg.pi_home, ".pi", "agent", rel]), content)
    end)
  end

  @doc "Eingebettete Dateien, Pfad relativ zu `<pi-home>/.pi/agent/` (für Tests)."
  @spec files() :: [{String.t(), String.t()}]
  def files, do: @files

  defp part_dir(cfg, part), do: Path.join([cfg.pi_home, ".pi", "agent", part])
end
