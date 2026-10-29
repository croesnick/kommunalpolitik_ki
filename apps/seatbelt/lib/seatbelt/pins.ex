defmodule Seatbelt.Pins do
  @moduledoc """
  Program pins: SHA-256 of every program a sandbox launcher starts.

  A generated sandbox profile is only as trustworthy as the programs it
  allows. Pinning makes each program's bytes part of the recorded state:
  hash every entry program (and, for packaged programs, the whole
  package tree), record the hashes, and refuse to start when the bytes
  at the same path have changed since. A dependency update then becomes
  a deliberate change, not a silent swap.

  What to pin is caller knowledge (entry programs, package roots); this
  module only hashes and classifies.
  """

  alias Seatbelt

  @type pin :: %{String.t() => String.t()}
  @type pins :: %{String.t() => pin()}

  @doc """
  Current pins for `[{name, path}]`: `%{name => %{"path" => path, "sha256" => hash}}`.
  Entries whose path cannot be hashed are skipped (the caller decides
  whether that is an error).
  """
  @spec compute([{String.t(), String.t()}]) :: pins()
  def compute(artifacts) do
    for {name, path} <- artifacts, {:ok, hash} <- [hash(path)], into: %{} do
      {name, %{"path" => path, "sha256" => hash}}
    end
  end

  @doc """
  Deviations of `current` against `pinned`: `:new` (not recorded yet, or
  at a new path, e.g. after `brew upgrade`) and `:changed` (same path,
  different bytes). Programs that disappeared do not count.
  """
  @spec drift(pins(), pins()) :: %{new: [String.t()], changed: [String.t()]}
  def drift(pinned, current) do
    Enum.reduce(Enum.sort(current), %{new: [], changed: []}, fn
      {name, %{"path" => path} = pin}, acc ->
        case Map.get(pinned, name) do
          ^pin -> acc
          %{"path" => ^path} -> %{acc | changed: acc.changed ++ [name]}
          _ -> %{acc | new: acc.new ++ [name]}
        end
    end)
  end

  @doc "SHA-256 of a file or, for a directory, of the whole tree."
  @spec hash(String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def hash(path) do
    case File.lstat(path) do
      {:ok, %File.Stat{type: :directory}} ->
        {:ok, hex(:crypto.hash(:sha256, tree_lines(path, "")))}

      {:ok, %File.Stat{type: :regular}} ->
        {:ok, hex(file_digest(path))}

      {:ok, %File.Stat{type: :symlink}} ->
        hash(Seatbelt.canonical(path))

      {:ok, _} ->
        {:error, "neither file nor directory"}

      {:error, reason} ->
        {:error, List.to_string(:file.format_error(reason))}
    end
  end

  # One line per entry, sorted: type, relative path, content hash or
  # symlink target. Renaming, adding, removing and retargeting a link
  # change the tree hash just like changed bytes do.
  defp tree_lines(root, rel) do
    root
    |> Path.join(rel)
    |> File.ls!()
    |> Enum.sort()
    |> Enum.map(fn entry ->
      rel_entry = if rel == "", do: entry, else: Path.join(rel, entry)
      full = Path.join(root, rel_entry)

      case File.lstat!(full) do
        %File.Stat{type: :directory} ->
          ["d\0", rel_entry, "\n", tree_lines(root, rel_entry)]

        %File.Stat{type: :symlink} ->
          {:ok, target} = :file.read_link(full)
          ["l\0", rel_entry, "\0", to_string(target), "\n"]

        %File.Stat{type: :regular} ->
          ["f\0", rel_entry, "\0", hex(file_digest(full)), "\n"]

        _ ->
          ["o\0", rel_entry, "\n"]
      end
    end)
  end

  defp file_digest(path) do
    path
    |> File.stream!(1024 * 1024)
    |> Enum.reduce(:crypto.hash_init(:sha256), &:crypto.hash_update(&2, &1))
    |> :crypto.hash_final()
  end

  defp hex(digest), do: Base.encode16(digest, case: :lower)
end
