defmodule KomkiCli.PiTest do
  # Reine Funktionen auf einer cfg aus Config.defaults — kein globaler Zustand;
  # die readlink-Kanonisierung ist total (auch auf Hosts ohne die gepinnten Pfade).
  use ExUnit.Case, async: true

  alias KomkiCli.{Pi, TestSupport}

  setup do
    {:ok, cfg: TestSupport.fixture_cfg(TestSupport.tmp_area!("komki-pi"))}
  end

  describe "Einmal-Lauf (argv_for): headless, stdin aus /dev/null" do
    test "sh-Redirect-Konvention und Direktkette", %{cfg: cfg} do
      argv = Pi.argv_for(cfg, "/scratch", :text, "hallo")

      assert List.starts_with?(argv, [
               cfg.sandbox_exec,
               "-f",
               Pi.profile_path_for(cfg, "/scratch"),
               "--",
               "/bin/sh",
               "-c",
               "exec \"$0\" \"$@\" < /dev/null",
               cfg.node_bin,
               cfg.cli_js
             ])

      assert Enum.any?(argv, &String.contains?(&1, "< /dev/null"))
      assert "--print" in argv
      assert "--no-session" in argv
      assert List.last(argv) == "hallo"
    end

    test "MCP-Vertrag (Ticket #102): -e builtin:mcp direkt nach --no-extensions", %{cfg: cfg} do
      # Einmal-Lauf: die einzigen werksetzenden Aufrufe sind pi_flags/2
      # hinter argv_for — der MCP-Vertrag gilt hier genauso wie in der Session.
      argv = Pi.argv_for(cfg, "/scratch", :text, "hallo")
      assert Enum.count(argv, &(&1 == "-e")) == 1

      idx = Enum.find_index(argv, &(&1 == "--no-extensions"))
      assert Enum.slice(argv, idx, 3) == ["--no-extensions", "-e", "builtin:mcp"]

      # Tools-Allowlist: write plus die Vermittler-Tools (Ticket #133)
      idx_tools = Enum.find_index(argv, &(&1 == "--tools"))
      assert Enum.at(argv, idx_tools + 1) == "write,mcp__komki__*"
    end
  end

  describe "run_with_timeout/5 (Ticket #133)" do
    test "normaler Lauf liefert stdout und Status 0" do
      assert {:ok, "hallo\n"} = Pi.run_with_timeout("/bin/echo", ["hallo"], %{}, "/", 5_000)
    end

    test "Fehlerstatus wird durchgereicht" do
      assert {:error, "", 1} = Pi.run_with_timeout("/usr/bin/false", [], %{}, "/", 5_000)
    end

    test "Limit beendet den Prozess mit Status 124" do
      {micros, result} =
        :timer.tc(fn -> Pi.run_with_timeout("/bin/sleep", ["30"], %{}, "/", 300) end)

      assert {:error, out, 124} = result
      assert out =~ "Laufzeit-Limit"
      assert micros < 5_000_000
    end
  end

  describe "Kontextdateien (Ticket #133)" do
    test "run und session schalten AGENTS.md/CLAUDE.md-Discovery ab", %{cfg: cfg} do
      assert "--no-context-files" in Pi.argv_for(cfg, "/scratch", :text, "hallo")

      for continue? <- [false, true] do
        assert "--no-context-files" in Pi.argv_session(cfg, continue?)
      end
    end
  end

  describe "Session (argv_session/2): interaktiv, echte Pty" do
    test "kein --print, kein --no-session, kein stdin-Redirect", %{cfg: cfg} do
      argv = Pi.argv_session(cfg, false)

      refute "--print" in argv
      refute "--no-session" in argv
      refute Enum.any?(argv, &String.contains?(&1, "/dev/null"))
    end

    test "MCP-Vertrag (Ticket #102): -e builtin:mcp direkt nach --no-extensions", %{cfg: cfg} do
      for continue? <- [false, true] do
        argv = Pi.argv_session(cfg, continue?)

        idx = Enum.find_index(argv, &(&1 == "--no-extensions"))
        assert Enum.slice(argv, idx, 3) == ["--no-extensions", "-e", "builtin:mcp"]
      end
    end

    test "genau zwei Extensions: builtin:mcp und die Anzeige aus dem pi-Home", %{cfg: cfg} do
      for continue? <- [false, true] do
        argv = Pi.argv_session(cfg, continue?)

        extensions =
          argv
          |> Enum.with_index()
          |> Enum.filter(fn {arg, _} -> arg == "-e" end)
          |> Enum.map(fn {_, i} -> Enum.at(argv, i + 1) end)

        assert extensions == ["builtin:mcp", KomkiCli.Anzeige.entry(cfg)]
        assert String.starts_with?(KomkiCli.Anzeige.entry(cfg), cfg.pi_home)
      end
    end

    test "Direktkette ohne sh-Hop; session-dir unter pi-home", %{cfg: cfg} do
      argv = Pi.argv_session(cfg, false)

      assert List.starts_with?(
               argv,
               [
                 cfg.sandbox_exec,
                 "-f",
                 Pi.session_profile_path(cfg),
                 "--",
                 cfg.node_bin,
                 cfg.cli_js
               ]
             )

      refute "/bin/sh" in argv

      idx = Enum.find_index(argv, &(&1 == "--session-dir"))
      assert Enum.at(argv, idx + 1) == Pi.session_dir(cfg)
    end

    test "--continue nur auf Wunsch und vor den Basis-Flags", %{cfg: cfg} do
      argv = Pi.argv_session(cfg, true)

      assert Enum.find_index(argv, &(&1 == "--continue")) <
               Enum.find_index(argv, &(&1 == "--provider"))

      refute "--continue" in Pi.argv_session(cfg, false)
    end

    test "System-Prompt: knapper, deutscher, vor Provider-Angabe", %{cfg: cfg} do
      argv = Pi.argv_session(cfg, false)

      idx = Enum.find_index(argv, &(&1 == "--system-prompt"))
      assert is_integer(idx)
      assert idx < Enum.find_index(argv, &(&1 == "--provider"))

      prompt = Enum.at(argv, idx + 1)
      assert String.contains?(prompt, "Deutsch")
      assert String.contains?(prompt, "Du-Form")
      assert String.contains?(prompt, "kommunalpolitische")
    end

    test "Tool-Allowlist: ls immer, find/grep nur mit entdeckter Binary", %{cfg: cfg} do
      argv = Pi.argv_session(cfg, false)

      idx = Enum.find_index(argv, &(&1 == "--tools"))
      assert Enum.at(argv, idx + 1) == "read,write,ls,find,grep,mcp__komki__*"

      bare = Pi.argv_session(%{cfg | fd_bin: nil, rg_bin: nil}, false)

      idx_bare = Enum.find_index(bare, &(&1 == "--tools"))
      assert Enum.at(bare, idx_bare + 1) == "read,write,ls,mcp__komki__*"
    end

    test "pane_command: Escript-Pfad + session-chain, sh-gequotet" do
      assert Pi.pane_command("/tmp/komki", false) == "'/tmp/komki' 'session-chain'"

      assert Pi.pane_command("/tmp/komki", true) ==
               "'/tmp/komki' 'session-chain' '--continue'"
    end

    # Burrito-Session-Fix (Pilot 2026-10-11): unter der Binary ist das
    # BEAM-stdout die Wrapper-Pipe, pi braucht aber ein TTY auf stdout —
    # deshalb biegt die Kette stdout auf /dev/fd/0 (Dup des lebenden
    # stdin-PTY) um. Der Escript-Pfad (stdout = Pane-PTY) bleibt exakt
    # wie vorher.
    test "argv_session/3 ohne Redirect: identisch mit der 2-stelligen Form", %{cfg: cfg} do
      assert Pi.argv_session(cfg, true) == Pi.argv_session(cfg, true, false)
      assert Pi.argv_session(cfg, false) == Pi.argv_session(cfg, false, false)

      refute "/bin/sh" in Pi.argv_session(cfg, false, false)
    end

    test "argv_session/3 mit tty_redirect: sh-c-Kette leitet stdout auf /dev/fd/0", %{cfg: cfg} do
      argv = Pi.argv_session(cfg, false, true)

      assert List.starts_with?(
               argv,
               [
                 cfg.sandbox_exec,
                 "-f",
                 Pi.session_profile_path(cfg),
                 "--",
                 "/bin/sh",
                 "-c",
                 ~s(exec "$0" "$@" > /dev/fd/0)
               ]
             )

      # $0 = node, $@ = cli.js + Flags; Direktkette bleibt der sh-Zweig
      assert Enum.at(argv, 7) == cfg.node_bin
      assert Enum.at(argv, 8) == cfg.cli_js

      idx = Enum.find_index(argv, &(&1 == "--session-dir"))
      assert Enum.at(argv, idx + 1) == Pi.session_dir(cfg)

      refute Enum.any?(argv, &String.contains?(&1, "/dev/null"))
      refute "--continue" in argv
    end

    test "argv_session/3 mit tty_redirect und --continue: Flag bleibt vor Provider", %{cfg: cfg} do
      argv = Pi.argv_session(cfg, true, true)

      assert Enum.find_index(argv, &(&1 == "--continue")) <
               Enum.find_index(argv, &(&1 == "--provider"))
    end

    test "env_list: deterministisch sortiert, Kernvariablen gesetzt", %{cfg: cfg} do
      env = Pi.env_list(cfg)

      assert {"HOME", cfg.pi_home} in env
      assert {"PI_OFFLINE", "1"} in env
      assert {"PATH", "/usr/bin:/bin"} in env
      assert {"JITI_FS_CACHE", "false"} in env
      assert Enum.sort(env) == env
    end
  end
end
