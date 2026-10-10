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
  end

  describe "Session (argv_session/2): interaktiv, echte Pty" do
    test "kein --print, kein --no-session, kein stdin-Redirect", %{cfg: cfg} do
      argv = Pi.argv_session(cfg, false)

      refute "--print" in argv
      refute "--no-session" in argv
      refute Enum.any?(argv, &String.contains?(&1, "/dev/null"))
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
      assert Enum.at(argv, idx + 1) == "read,write,ls,find,grep"

      bare = Pi.argv_session(%{cfg | fd_bin: nil, rg_bin: nil}, false)

      idx_bare = Enum.find_index(bare, &(&1 == "--tools"))
      assert Enum.at(bare, idx_bare + 1) == "read,write,ls"
    end

    test "pane_command: Escript-Pfad + session-chain, sh-gequotet" do
      assert Pi.pane_command("/tmp/komki", false) == "'/tmp/komki' 'session-chain'"

      assert Pi.pane_command("/tmp/komki", true) ==
               "'/tmp/komki' 'session-chain' '--continue'"
    end

    test "env_list: deterministisch sortiert, Kernvariablen gesetzt", %{cfg: cfg} do
      env = Pi.env_list(cfg)

      assert {"HOME", cfg.pi_home} in env
      assert {"PI_OFFLINE", "1"} in env
      assert {"PATH", "/usr/bin:/bin"} in env
      assert Enum.sort(env) == env
    end
  end
end
