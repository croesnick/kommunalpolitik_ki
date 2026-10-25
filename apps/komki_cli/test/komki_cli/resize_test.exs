defmodule KomkiCli.ResizeTest do
  use ExUnit.Case, async: true

  alias KomkiCli.{Resize, TestSupport}

  # Gleiche Signale verschmelzen, solange eins aussteht: je Weiterleitung
  # auf die Spur des Handlers warten, bevor die naechste kommt. perl statt
  # /bin/sh: bash 3.2 fuehrt einen WINCH-Trap nur einmal aus.
  defp await_lines(path, n, tries \\ 50) do
    lines =
      case File.read(path) do
        {:ok, text} -> String.split(text, "\n", trim: true)
        {:error, _} -> []
      end

    cond do
      length(lines) >= n -> length(lines)
      tries == 0 -> length(lines)
      true -> Process.sleep(50) && await_lines(path, n, tries - 1)
    end
  end

  test "SIGWINCH wird an pi weitergereicht, der Handler laeuft weiter" do
    mark = Path.join(TestSupport.tmp_area!("komki-resize"), "winch")

    port =
      Port.open({:spawn_executable, "/usr/bin/perl"},
        args: [
          "-e",
          ~S|$SIG{WINCH} = sub { system("echo x >> $ARGV[0]") }; sleep 1 while 1|,
          mark
        ]
      )

    {:os_pid, pid} = Port.info(port, :os_pid)
    on_exit(fn -> System.cmd("/bin/kill", ["-KILL", "#{pid}"], stderr_to_stdout: true) end)
    Process.sleep(200)

    assert {:ok, ^pid} = Resize.handle_event(:sigwinch, pid)
    assert await_lines(mark, 1) == 1
    assert {:ok, ^pid} = Resize.handle_event(:sigwinch, pid)
    assert await_lines(mark, 2) == 2
  end

  test "andere Signale laesst der Handler liegen" do
    assert {:ok, 1} = Resize.handle_event(:sighup, 1)
  end
end
