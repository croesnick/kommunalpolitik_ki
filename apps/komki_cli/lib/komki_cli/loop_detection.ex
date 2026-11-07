defmodule KomkiCli.LoopDetection do
  @moduledoc """
  pi extension `komki-loop-detection` (Ticket #383, source `priv/pi/`,
  embedded at compile time): stops a run when the model issues the same
  tool call five times in a row and tells the user why. pi itself has no
  limit on turns or tool calls. Loaded in `komki run` and `komki session`.

  Like `KomkiCli.Anzeige`, the files are written fresh into
  `<pi-home>/.pi/agent/` before every pi start, because the pi home is
  writable for the agent.
  """

  alias KomkiCli.Config

  @part "komki-loop-detection"
  @priv Path.expand("../../priv/pi/#{@part}", __DIR__)
  @files for name <- @priv |> File.ls!() |> Enum.sort(),
             do: {name, File.read!(Path.join(@priv, name))}
  for {name, _} <- @files, do: @external_resource(Path.join(@priv, name))

  @spec dir(Config.t()) :: String.t()
  def dir(%Config{} = cfg), do: Path.join([cfg.pi_home, ".pi", "agent", @part])

  @doc "Entry point for `pi -e`."
  @spec entry(Config.t()) :: String.t()
  def entry(%Config{} = cfg), do: Path.join(dir(cfg), "index.ts")

  @doc "pi flags that load the extension (after `--no-extensions`)."
  @spec flags(Config.t()) :: [String.t()]
  def flags(%Config{} = cfg), do: ["-e", entry(cfg)]

  @doc "Writes the extension fresh into the pi home; foreign files in its folder disappear."
  @spec write!(Config.t()) :: :ok
  def write!(%Config{} = cfg) do
    path = dir(cfg)
    File.rm_rf!(path)
    File.mkdir_p!(path)
    Enum.each(@files, fn {name, content} -> File.write!(Path.join(path, name), content) end)
  end

  @doc "Embedded files, names relative to the extension folder (for tests)."
  @spec files() :: [{String.t(), String.t()}]
  def files, do: @files
end
