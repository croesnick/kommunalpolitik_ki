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
#
# Takeover: every session gets its id up front. When the person asks for
# it (the takeover file), the headless session is ended and continues
# interactively under the same id, account and rules, in a Herdr tab or by
# hand; the loop treats the stage as handed to the human.

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

  # Stream-json reports events only for completed messages and tool
  # results, so one long command inside a session is silent however
  # healthy it is. The idle window must outlast the longest plausible
  # in-session command; sixty minutes do, while a dead CLI never
  # delivers another line at all. The final result line ends the stage
  # at once (finish_on below), so Claude Code's silent background wait
  # after the result can burn neither idle time nor wall clock.
  @idle_timeout_ms 60 * 60 * 1000
  @result_line ~s({"type":"result")

  # Variables of an outer Claude Code session or of the loop itself that a
  # stage must not inherit.
  @scrubbed ~w(GH_TOKEN GITHUB_TOKEN ANTHROPIC_AUTH_TOKEN ANTHROPIC_API_KEY CLAUDE_CONFIG_DIR
               CLAUDE_CODE_SESSION_ID CLAUDE_CODE_CHILD_SESSION CLAUDE_CODE_SESSION_ATTENDED
               CLAUDE_CODE_ENTRYPOINT CLAUDE_CODE_MESSAGING_SOCKET CLAUDE_CODE_MESSAGING_TOKEN)

  @doc """
  Runs `role` in `cwd` with the prompt file `.dev-loop/prompt.md`.
  Returns `{:ok, result}` (the final stream-json result object),
  `{:error, text}`, `{:taken_over, text}` when the person took the session
  over, or `:exhausted` when every account of the chain is used up. Throws
  `:stop` when the stop file exists.
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
    session = uuid4()
    stage = "#{Path.basename(cwd)}-#{role}-#{account}"
    ctx.log.("#{role}: #{account} startet (Session #{session}, Log: #{log})")

    args =
      ["-p", "Lies .dev-loop/prompt.md und führe den Auftrag dort vollständig aus."] ++
        ~w(--output-format stream-json --verbose --permission-mode auto --permission-prompts none
           --session-id #{session}) ++ rules(extra)

    outcome =
      ctx.watch.(stage, log, fn ->
        Proc.run("claude", args,
          cd: cwd,
          env: env(account),
          timeout_ms: ctx.stage_timeout_ms,
          idle_ms: @idle_timeout_ms,
          finish_on: @result_line,
          log: log,
          # Consumed by the stage that sees it, so it takes over one stage.
          cancel: fn -> File.rm(ctx.takeover_file) == :ok end
        )
      end)

    case classify(outcome) do
      :exhausted ->
        ctx.log.("#{role}: #{account} ist erschöpft, nächstes Konto")
        try_chain(rest, role, cwd, ctx)

      :taken_over ->
        ctx.take_over.("#{stage}-hand", cwd, resume_command(account, session, extra))
        ctx.log.("#{role}: von Hand übernommen (Session #{session})")
        {:taken_over, taken_over_text(account, session, cwd)}

      {:ok, result} = ok ->
        note_metrics(result, role, account, cwd, ctx)
        ok

      other ->
        other
    end
  end

  # The same rules for the headless session and for its interactive
  # continuation after a takeover. The repo's .claude/settings.json is meant
  # for interactive sessions (#462) and would loosen this sandbox when merged
  # into it, so only user and local settings load besides @settings.
  defp rules(extra),
    do: ~w(--strict-mcp-config --setting-sources user,local --settings #{@settings}) ++ extra

  @doc """
  The shell command that continues `session` interactively: same account,
  model and rules. The tt token is read by the shell when the command
  runs, never put into the command itself.
  """
  def resume_command(account, session, extra) do
    exe = System.find_executable("claude") || "claude"

    vars =
      case account do
        :claude ->
          []

        :tt ->
          ["CLAUDE_CONFIG_DIR=#{q(@tt_dir)}", ~s[ANTHROPIC_AUTH_TOKEN="$(#{q(token_script())})"]]
      end

    Enum.join(
      ["env"] ++
        vars ++
        ["CLAUDE_CODE_DISABLE_AUTO_MEMORY=1", q(exe), "--resume", q(session)] ++
        Enum.map(~w(--permission-mode auto) ++ rules(extra), &q/1),
      " "
    )
  end

  defp taken_over_text(account, session, cwd) do
    """
    Von Hand übernommen: Session `#{session}` (Konto `#{account}`) in `#{cwd}`.
    Weiter von Hand: `cd #{q(cwd)} && #{account} --resume #{session}`
    """
  end

  defp classify({:timeout, _}), do: {:error, "Zeitlimit der Stufe überschritten"}

  defp classify({:idle, _}),
    do: {:error, "seit #{div(@idle_timeout_ms, 60_000)} Minuten keine Ausgabe"}

  defp classify({:cancelled, _}), do: :taken_over
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
    case System.cmd(token_script(), [], stderr_to_stdout: false) do
      {token, 0} -> String.trim(token)
      _ -> raise "tt: Token-Skript fehlgeschlagen"
    end
  end

  defp token_script, do: Path.join(@tt_dir, "anthropic-token.sh")

  # One line per successful stage run, appended to metrics.jsonl in the
  # run's log directory (core.exs turns them into the morning comment's
  # statistics). Failed and exhausted attempts have no result event to
  # read and stay uncounted.
  defp note_metrics(result, role, account, cwd, ctx) do
    line =
      %{
        stage: role,
        issue: issue_from_cwd(cwd),
        account: account,
        turns: result["num_turns"],
        duration_ms: result["duration_ms"],
        tokens_in: get_in(result, ["usage", "input_tokens"]),
        tokens_out: get_in(result, ["usage", "output_tokens"])
      }
      |> Map.reject(fn {_k, v} -> is_nil(v) end)
      |> JSON.encode!()

    File.write!(Path.join(ctx.logs, "metrics.jsonl"), line <> "\n", [:append])
  end

  # Worktree names carry the ticket: loop-392, loop-392-review. The PO
  # worktree and the sandbox probe have none.
  defp issue_from_cwd(cwd) do
    case Regex.run(~r/^loop-(\d+)/, Path.basename(cwd)) do
      [_, n] -> String.to_integer(n)
      nil -> nil
    end
  end

  # A random (version 4) UUID, the form --session-id wants.
  defp uuid4 do
    <<a::48, _::4, b::12, _::2, c::62>> = :crypto.strong_rand_bytes(16)
    hex = Base.encode16(<<a::48, 4::4, b::12, 2::2, c::62>>, case: :lower)
    <<p1::binary-8, p2::binary-4, p3::binary-4, p4::binary-4, p5::binary-12>> = hex
    Enum.join([p1, p2, p3, p4, p5], "-")
  end

  defp q(s), do: "'" <> String.replace(s, "'", ~S('\'')) <> "'"
end
