# elixir scripts/dev_loop/test/viewer_test.exs   (needs jq)

ExUnit.start()
Code.require_file("../herdr.exs", __DIR__)

defmodule DevLoop.ViewerTest do
  use ExUnit.Case, async: true

  @viewer Path.expand("../viewer.jq", __DIR__)

  # Shapes as Claude Code's stream-json writes them (checked against the
  # stage logs of 2026-11-07).
  @events [
    "Warning: no stdin data received in 3s, proceeding without it.",
    ~s({"type":"system","subtype":"init","model":"claude-sonnet-5-5","cwd":"/wt/loop-392"}),
    ~s({"type":"system","subtype":"hook_started"}),
    ~s({"type":"assistant","message":{"content":[{"type":"thinking","thinking":"x"}]}}),
    ~s({"type":"assistant","message":{"content":[{"type":"text","text":"Keine geschützten Pfade."}]}}),
    ~s({"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"mix test"}}]}}),
    ~s({"type":"user","message":{"content":[{"type":"tool_result","content":"418 tests,\\n0 failures"}]}}),
    ~s({"type":"user","message":{"content":[{"type":"tool_result","is_error":true,"content":[{"type":"text","text":"Permission denied"}]}]}}),
    ~s({"type":"user","message":{"content":"plain string content"}}),
    ~s({"type":"result","is_error":false,"num_turns":30,"duration_ms":354835,"permission_denials":[{"tool_input":{"command":"gh api user"}}]})
  ]

  defp render(lines, args \\ []) do
    path = Path.join(System.tmp_dir!(), "viewer-#{System.unique_integer([:positive])}.jsonl")
    File.write!(path, Enum.join(lines, "\n") <> "\n")
    {out, 0} = System.cmd("jq", ["-rR"] ++ args ++ ["-f", @viewer, path])
    File.rm!(path)
    out |> String.replace(~r/\e\[\d+m/, "") |> String.split("\n", trim: true)
  end

  # OSC 7501 reports in the output, decoded: {state, msg}.
  defp reports(lines) do
    for line <- lines, [_, fields] <- [Regex.run(~r/\e\]7501;([^\e]*)\e\\/, line)] do
      kv =
        for f <- String.split(fields, ":"),
            [k, v] = String.split(f, "=", parts: 2),
            into: %{},
            do: {k, v}

      assert kv["app"] == "claude-code"
      assert Base.decode64!(kv["title"]) == "loop-333-implement-claude"
      {kv["state"], Base.decode64!(kv["msg"])}
    end
  end

  test "renders model, text, tool calls, results and denials; skips the rest" do
    assert render(@events) == [
             "▶ claude-sonnet-5-5 · /wt/loop-392",
             "· denkt",
             "Keine geschützten Pfade.",
             "→ Bash mix test",
             "  ✓ 418 tests, 0 failures",
             "  ✗ Permission denied",
             "■ fertig · 30 Turns · 354 s",
             "  abgelehnt: gh api user"
           ]
  end

  test "without status the output has no OSC 7501 report" do
    refute Enum.any?(render(@events), &String.contains?(&1, "\e]7501"))
  end

  test "with status it reports start, every tool call and the end like Claude Code" do
    lines = render(@events, ~w(--arg status 1 --arg title loop-333-implement-claude))

    assert reports(lines) == [
             {"working", "startet"},
             {"working", "Bash mix test"},
             {"done", "fertig"}
           ]

    error = ~s({"type":"result","is_error":true,"num_turns":1,"duration_ms":1000})

    assert reports(render([error], ~w(--arg status 1 --arg title loop-333-implement-claude))) == [
             {"error", "Fehler"}
           ]
  end

  test "long tool arguments are cut" do
    long = String.duplicate("a", 300)

    [line] =
      render([
        ~s({"type":"assistant","message":{"content":[{"type":"tool_use","name":"Read","input":{"file_path":"#{long}"}}]}})
      ])

    assert String.length(line) == String.length("→ Read ") + 160 + 1
    assert String.ends_with?(line, "…")
  end

  test "terminal names fit hc's rules" do
    assert DevLoop.Herdr.terminal_name("loop-392-review-claude") == "loop-392-review-claude"
    assert DevLoop.Herdr.terminal_name("Loop 392 · Review") == "loop-392-review"
    assert String.length(DevLoop.Herdr.terminal_name(String.duplicate("a", 50))) == 32
  end

  test "the viewer command quotes paths for the shell" do
    assert DevLoop.Herdr.viewer_command("/logs/it's here.jsonl", "loop-1") =~
             ~S(tail -n +1 -F '/logs/it'\''s here.jsonl' | jq -rR --unbuffered --arg status 1 --arg title 'loop-1' -f ')
  end
end
