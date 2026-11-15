defmodule KomkiMock.StateDir do
  @moduledoc """
  Rights and placement of the mock's state directory (Ticket #481, Fund F9).

  Everything the mock persists — replayed cassette bodies, accepted mock
  tokens, the request log — stays owner-only, mirroring what
  `ris_recorder.exs` already guarantees for its cassettes: files 0600,
  directory 0700, and no state inside a Git repository (`git add -A` would
  swallow real non-public council content; the recorder refuses such an
  `--out` outright).
  """

  @replay KomkiMock.Adapters.Replay

  @doc """
  Checks the state directory before the first write, for cassettes via the
  Replay adapter (#481): refuses a `--dir` inside a Git repository and
  warns about an existing world-readable directory before hardening it.
  Other adapters keep working unchanged.
  """
  @spec check(module(), Path.t()) :: :ok | {:error, String.t()}
  def check(adapter, dir) do
    if adapter == @replay do
      case repo_free(dir) do
        :ok -> warn_world_readable(dir)
        {:error, _reason} = error -> error
      end
    else
      :ok
    end
  end

  @doc "Creates or hardens the state directory: 0700, owner-only."
  @spec prepare!(Path.t()) :: :ok
  def prepare!(dir) do
    File.mkdir_p!(dir)
    File.chmod!(dir, 0o700)
    :ok
  end

  # `:ok` when `dir` lies outside every Git repository (worktrees included:
  # their `.git` is a file), otherwise an error naming the repo. Mirrors
  # KomkiConnectorRis.RisHttp.repo_free?/1 (priv script, not a dependency):
  # existing paths resolve through symlinks, a not-yet-existing tail stays
  # lexical on its longest existing ancestor.
  defp repo_free(dir) do
    case in_repo?(Path.expand(dir)) do
      nil ->
        :ok

      repo ->
        {:error,
         "Zustandsverzeichnis #{dir} liegt im Git-Repo #{repo}; Kassetten enthalten " <>
           "nicht-öffentliche Daten und gehören außerhalb jedes Repos"}
    end
  end

  defp in_repo?(path) do
    path
    |> resolved()
    |> ancestors()
    |> Enum.find(&File.exists?(Path.join(&1, ".git")))
  end

  defp resolved(path), do: resolved_loop(path, 0)

  defp resolved_loop(path, hops) when hops >= 64, do: path

  defp resolved_loop(path, hops) do
    case File.read_link(path) do
      {:ok, target} ->
        resolved_loop(Path.expand(target, Path.dirname(path)), hops + 1)

      {:error, _reason} ->
        case Path.dirname(path) do
          ^path -> path
          parent -> Path.join(resolved_loop(parent, hops + 1), Path.basename(path))
        end
    end
  end

  defp ancestors(path) do
    parent = Path.dirname(path)
    if parent == path, do: [path], else: [path | ancestors(parent)]
  end

  defp warn_world_readable(dir) do
    case File.stat(dir) do
      {:ok, %File.Stat{mode: mode}} ->
        if Bitwise.band(mode, 0o004) != 0 do
          IO.puts(
            :stderr,
            "Warnung: Zustandsverzeichnis #{dir} war weltlesbar; der Mock härtet es auf 0700"
          )
        end

        :ok

      {:error, _reason} ->
        :ok
    end
  end
end
