defmodule KomkiCli.HangupTest do
  use ExUnit.Case, async: true

  alias KomkiCli.{Config, Hangup, Steps, TestSupport}

  defp spawn_sh(cmd) do
    port = Port.open({:spawn_executable, "/bin/sh"}, args: ["-c", cmd])
    {:os_pid, pid} = Port.info(port, :os_pid)
    pid
  end

  defp alive?(pid),
    do: match?({_, 0}, System.cmd("/bin/kill", ["-0", "#{pid}"], stderr_to_stdout: true))

  test "stop_pi beendet pi, auch wenn es TERM ignoriert (KILL nach der Schonfrist)" do
    pid = spawn_sh("trap '' TERM; while :; do sleep 1; done")
    Process.sleep(200)
    assert :ok = Hangup.stop_pi(pid, 300)
    Process.sleep(200)
    refute alive?(pid)
  end

  test "reap_orphans: ohne passende Relays nichts zu tun" do
    relay = Path.join(TestSupport.tmp_area!("komki-reap"), "pi-home/.pi/agent/komki-relay.js")
    assert Hangup.reap_orphans(relay) == 0
  end

  describe "tmux_socket/1 (ein Server je Instanz)" do
    test "Standard-Instanz behaelt den Namen komki" do
      base = Path.join(Config.canonical(System.user_home!()), ".local/share/komki")
      assert Steps.tmux_socket(%{Config.defaults(base) | base_dir: base}) == "komki"
    end

    test "andere Instanzen bekommen verschiedene, stabile Namen" do
      a = Config.defaults(TestSupport.tmp_area!("komki-tmux-a"))
      b = Config.defaults(TestSupport.tmp_area!("komki-tmux-b"))

      assert Steps.tmux_socket(a) =~ ~r/^komki-[0-9a-f]{8}$/
      assert Steps.tmux_socket(a) == Steps.tmux_socket(a)
      refute Steps.tmux_socket(a) == Steps.tmux_socket(b)
    end
  end
end
