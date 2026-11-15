defmodule Ratsprojekte.PromptTest do
  # Echo suppression for the recovery code (Ticket #492, audit #467 F23):
  # `secret/2` mirrors KomkiCli.Prompt.secret/1 — `stty -echo` runs over a
  # `:nouse_stdio` port on fd 0 of the emulator, the echo is restored after
  # the read in every case, and without a terminal the input is refused
  # instead of reading the database's master key with echo on.
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  alias Ratsprojekte.Prompt

  defp stty(test),
    do: fn arg ->
      send(test, {:stty, arg})
      0
    end

  defp no_tty(test),
    do: fn arg ->
      send(test, {:stty, arg})
      1
    end

  # The stty calls in their order, as the person's terminal sees them.
  defp stty_aufrufe do
    receive do
      {:stty, arg} -> [arg | stty_aufrufe()]
    after
      0 -> []
    end
  end

  test "verdeckt: Echo aus vor der Eingabe, danach wieder an" do
    test = self()

    ausgabe =
      capture_io("super-geheim\n", fn ->
        send(test, {:ergebnis, Prompt.secret("Wiederherstellungscode: ", stty(test))})
      end)

    assert_received {:ergebnis, {:ok, "super-geheim"}}
    assert stty_aufrufe() == ["-echo", "echo"]
    assert ausgabe =~ "Wiederherstellungscode: "
    refute ausgabe =~ "super-geheim"
  end

  test "ohne Terminal: keine Eingabe, Echo unverändert" do
    test = self()

    # Without a terminal nothing is read — not even the prompt goes out.
    ausgabe =
      capture_io(fn ->
        send(test, {:ergebnis, Prompt.secret("Wiederherstellungscode: ", no_tty(test))})
      end)

    assert_received {:ergebnis, {:error, :no_tty}}
    assert stty_aufrufe() == ["-echo"]
    assert ausgabe == ""
  end

  test "leere Eingabe: Fehler, Echo trotzdem wiederhergestellt" do
    test = self()

    capture_io("\n", fn ->
      send(test, {:ergebnis, Prompt.secret("Wiederherstellungscode: ", stty(test))})
    end)

    assert_received {:ergebnis, {:error, :empty}}
    assert stty_aufrufe() == ["-echo", "echo"]
  end
end
