defmodule KomkiCli.PromptTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  alias KomkiCli.Prompt

  defp terminal, do: true
  defp no_terminal, do: false

  test "am Terminal: Enter gibt den Default, j/n entscheiden" do
    capture_io("\n", fn -> assert Prompt.confirm("?", true, &terminal/0) end)
    capture_io("\n", fn -> refute Prompt.confirm("?", false, &terminal/0) end)
    capture_io("j\n", fn -> assert Prompt.confirm("?", false, &terminal/0) end)
    capture_io("n\n", fn -> refute Prompt.confirm("?", true, &terminal/0) end)
  end

  test "ohne Eingabe (stdin zu Ende) immer nein, auch bei Default-Ja" do
    capture_io("", fn -> refute Prompt.confirm("?", true, &terminal/0) end)
  end

  # Ticket #262: `yes j | komki setup` darf weder Download noch Pins
  # uebernehmen. Ohne Terminal wird die Eingabe gar nicht gelesen.
  test "ohne Terminal nein, auch wenn ein Ja hineingepipt wird" do
    out =
      capture_io("j\nj\nj\n", fn ->
        refute Prompt.confirm("übernehmen?", false, &no_terminal/0)
        refute Prompt.confirm("herunterladen?", true, &no_terminal/0)
      end)

    assert out =~ "nein (kein Terminal"
  end
end
