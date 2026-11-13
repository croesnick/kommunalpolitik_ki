# Stop hook (#462): a session in this repo reports done only while the fast
# gates are green. Runs at the repo root, whatever directory the session is
# in. Skips when the working state equals origin/main or the last green state,
# and outside a git repo or without origin/main, so a turn without code
# changes costs a few git calls.
#
#   elixir .claude/hooks/stop_gates.exs run   # reads the hook JSON on stdin

defmodule StopGates do
  @gates [
    {"mix format --check-formatted", ~w(format --check-formatted)},
    {"Tests der betroffenen Apps", ~w(workspace.run -t test --affected --base origin/main)}
  ]

  def main do
    input = :stdio |> IO.read(:eof) |> JSON.decode!()
    {code, stdout, stderr} = run(input)
    IO.write(stdout)
    IO.write(:stderr, stderr)
    System.halt(code)
  end

  @doc "Returns `{exit_code, stdout, stderr}` for the hook input."
  def run(input, gates \\ &run_gates/1) do
    with {root, 0} <- git(input["cwd"] || File.cwd!(), ~w(rev-parse --show-toplevel)),
         root = String.trim(root),
         {base, 0} <- git(root, ~w(merge-base HEAD origin/main)),
         base = String.trim(base),
         {base_tree, 0} <- git(root, ["rev-parse", base <> "^{tree}"]),
         tree when is_binary(tree) <- state_tree(root),
         true <- tree != String.trim(base_tree),
         # The base is part of the key: when origin/main moves, the set of
         # affected apps may change.
         key = base <> " " <> tree,
         true <- key != last_green(root) do
      case gates.(root) do
        :ok ->
          File.write!(marker(root), key)
          {0, "", ""}

        {:error, name, output} ->
          verdict(input["stop_hook_active"] == true, name, output)
      end
    else
      _ -> {0, "", ""}
    end
  end

  @doc """
  Red gates block the first stop. While a stop hook already keeps the session
  going, the hook reports to the human instead, so it never loops.
  """
  def verdict(false, name, output) do
    {2, "",
     "Gate rot: #{name}. Behebe das, bevor du die Arbeit als fertig meldest.\n\n" <>
       excerpt(output)}
  end

  def verdict(true, name, _output) do
    message = "Stop-Hook: #{name} ist weiterhin rot. Die Session endet trotzdem."
    {0, JSON.encode!(%{systemMessage: message}), ""}
  end

  defp run_gates(cwd) do
    Enum.reduce_while(@gates, :ok, fn {name, args}, :ok ->
      case System.cmd("mix", args, cd: cwd, stderr_to_stdout: true) do
        {_, 0} -> {:cont, :ok}
        {output, _} -> {:halt, {:error, name, output}}
      end
    end)
  end

  # The tree of everything git would see after `git add -A`, without touching
  # the real index: tracked changes and untracked files that are not ignored.
  defp state_tree(cwd) do
    index = Path.join(System.tmp_dir!(), "stop-gates-#{System.unique_integer([:positive])}")
    env = [{"GIT_INDEX_FILE", index}]

    try do
      with {_, 0} <- System.cmd("git", ~w(read-tree HEAD), cd: cwd, env: env),
           {_, 0} <- System.cmd("git", ~w(add -A), cd: cwd, env: env),
           {tree, 0} <- System.cmd("git", ~w(write-tree), cd: cwd, env: env) do
        String.trim(tree)
      else
        _ -> nil
      end
    after
      File.rm(index)
    end
  end

  defp last_green(cwd) do
    case File.read(marker(cwd)) do
      {:ok, key} -> key
      _ -> :none
    end
  end

  defp marker(cwd) do
    {dir, 0} = git(cwd, ~w(rev-parse --absolute-git-dir))
    Path.join(String.trim(dir), "claude-stop-gates-green")
  end

  defp git(cwd, args), do: System.cmd("git", args, cd: cwd, stderr_to_stdout: true)

  @doc """
  The part of the gate output that explains red: failing tests with a few
  lines of context and the result lines, else the last lines.
  """
  def excerpt(output) do
    lines = output |> String.replace(~r/\e\[[0-9;]*m/, "") |> String.split("\n")

    failures =
      lines
      |> Enum.with_index()
      |> Enum.filter(fn {line, _} -> line =~ ~r/^\s+\d+\) / end)
      |> Enum.take(5)
      |> Enum.flat_map(fn {_, i} -> Enum.slice(lines, i, 12) end)

    results = Enum.filter(lines, &(&1 =~ ~r/^(==> |Result: |\d+ tests?, )/))

    case failures do
      [] -> lines |> Enum.take(-60) |> Enum.join("\n")
      _ -> Enum.join(failures ++ [""] ++ results, "\n")
    end
  end
end

if System.argv() == ["run"], do: StopGates.main()
