defmodule KomkiCli.PromptTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  alias KomkiCli.Prompt

  test "Enter gibt den Default, j/n entscheiden" do
    capture_io("\n", fn -> assert Prompt.confirm("?", true) end)
    capture_io("\n", fn -> refute Prompt.confirm("?", false) end)
    capture_io("j\n", fn -> assert Prompt.confirm("?", false) end)
    capture_io("n\n", fn -> refute Prompt.confirm("?", true) end)
  end

  test "ohne Eingabe (stdin zu Ende) immer nein, auch bei Default-Ja" do
    capture_io("", fn -> refute Prompt.confirm("?", true) end)
  end
end
