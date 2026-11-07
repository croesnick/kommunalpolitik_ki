# Headless agent sessions of the dev loop (#389). One session per stage,
# always fresh. A role has a chain of accounts: when the first one hits its
# usage limit, the same stage starts again on the next one.
#
#   implement: claude (Sonnet 5.5)  → tt (default model)
#   review/po: claude (Opus 5.5)    → tt (default model, max effort)
#
# `tt` is the person's zsh function around claude with its own config
# directory and token; it is rebuilt here because a port cannot call a
# shell function. Agents run in auto mode with the Bash sandbox and the
# deny rules of agent_settings.json, without MCP servers and without any
# GitHub token in their environment.

defmodule DevLoop.Agent do
  @moduledoc false

  alias DevLoop.{Core, Proc}

  @settings Path.expand("agent_settings.json", __DIR__)
  @tt_dir Path.expand("~/.claude-tt")

  @chains %{
    implement: [{:claude, ["--model", "claude-sonnet-5-5"]}, {:tt, []}],
    review: [{:claude, ["--model", "claude-opus-5-5"]}, {:tt, ["--effort", "max"]}],
    po: [{:claude, ["--model", "claude-opus-5-5"]}, {:tt, ["--effort", "max"]}]
  }

  # Variables of an outer Claude Code session or of the loop itself that a
  # stage must not inherit.
  @scrubbed ~w(GH_TOKEN GITHUB_TOKEN ANTHROPIC_AUTH_TOKEN ANTHROPIC_API_KEY CLAUDE_CONFIG_DIR
               CLAUDE_CODE_SESSION_ID CLAUDE_CODE_CHILD_SESSION CLAUDE_CODE_SESSION_ATTENDED
               CLAUDE_CODE_ENTRYPOINT CLAUDE_CODE_MESSAGING_SOCKET CLAUDE_CODE_MESSAGING_TOKEN)

  @doc """
  Runs `role` in `cwd` with the prompt file `.dev-loop/prompt.md`.
  Returns `{:ok, result}` (the final stream-json result object),
  `{:error, text}` or `:exhausted` when every account of the chain is used up.
  Throws `:stop` when the stop file exists.
  """
  def run(role, prompt, cwd, ctx) do
    if File.exists?(ctx.stop_file), do: throw(:stop)
    File.mkdir_p!(Path.join(cwd, ".dev-loop"))
    File.write!(Path.join(cwd, ".dev-loop/prompt.md"), prompt)
    try_chain(chain(role, ctx[:account]), role, cwd, ctx)
  end

  # `--account` pins one account of the chain, e.g. to probe the sandbox on tt.
  defp chain(role, nil), do: Map.fetch!(@chains, role)

  defp chain(role, account),
    do: for({^account, _} = entry <- Map.fetch!(@chains, role), do: entry)

  defp try_chain([], _role, _cwd, _ctx), do: :exhausted

  defp try_chain([{account, extra} | rest], role, cwd, ctx) do
    log = Path.join(ctx.logs, "#{ctx.stamp.()}-#{role}-#{account}.jsonl")
    ctx.log.("#{role}: #{account} startet (Log: #{log})")

    args =
      ["-p", "Lies .dev-loop/prompt.md und führe den Auftrag dort vollständig aus."] ++
        ~w(--output-format stream-json --verbose --permission-mode auto --permission-prompts none
           --strict-mcp-config --settings #{@settings}) ++ extra

    outcome =
      ctx.watch.("#{Path.basename(cwd)}-#{role}-#{account}", log, fn ->
        Proc.run("claude", args,
          cd: cwd,
          env: env(account),
          timeout_ms: ctx.stage_timeout_ms,
          log: log
        )
      end)

    case classify(outcome) do
      :exhausted ->
        ctx.log.("#{role}: #{account} ist erschöpft, nächstes Konto")
        try_chain(rest, role, cwd, ctx)

      other ->
        other
    end
  end

  defp classify({:timeout, _}), do: {:error, "Zeitlimit der Stufe überschritten"}
  defp classify({:ok, lines}), do: classify_lines(lines)
  defp classify({:error, _status, lines}), do: classify_lines(lines)

  # A successful result is trusted even if its text mentions a limit; only
  # a failed session is checked for usage-limit messages.
  defp classify_lines(lines) do
    case lines |> Enum.reverse() |> Enum.find_value(&result_event/1) do
      %{"is_error" => false} = result ->
        {:ok, result}

      result ->
        text =
          if result,
            do: to_string(result["result"] || inspect(result["errors"])),
            else: Enum.join(Enum.take(lines, -20), "\n")

        if Core.exhausted?(text), do: :exhausted, else: {:error, String.slice(text, -2000, 2000)}
    end
  end

  defp result_event(line) do
    case JSON.decode(line) do
      {:ok, %{"type" => "result"} = r} -> r
      _ -> nil
    end
  end

  defp env(account) do
    base = for(name <- @scrubbed, do: {name, false}) ++ [{"CLAUDE_CODE_DISABLE_AUTO_MEMORY", "1"}]

    case account do
      :claude -> base
      :tt -> base ++ [{"CLAUDE_CONFIG_DIR", @tt_dir}, {"ANTHROPIC_AUTH_TOKEN", tt_token()}]
    end
  end

  defp tt_token do
    case System.cmd(Path.join(@tt_dir, "anthropic-token.sh"), [], stderr_to_stdout: false) do
      {token, 0} -> String.trim(token)
      _ -> raise "tt: Token-Skript fehlgeschlagen"
    end
  end
end
