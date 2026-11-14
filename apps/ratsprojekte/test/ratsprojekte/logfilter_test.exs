defmodule Ratsprojekte.LogfilterTest do
  # Installs a primary logger filter, hence not async.
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  require Logger

  setup do
    :ok = Ratsprojekte.Logfilter.installieren()
    on_exit(fn -> :logger.remove_primary_filter(:inhaltsfrei) end)
  end

  test "eigene, als inhaltsfrei erklärte Meldungen bleiben stehen" do
    # credo:disable-for-next-line Credo.Check.Warning.MissedMetadataKeyInLoggerConfig
    log = capture_log(fn -> Logger.warning("Migration fehlgeschlagen", inhaltsfrei: true) end)
    assert log =~ "Migration fehlgeschlagen"
  end

  test "alles andere verliert die Meldung: keine Inhalte, keine Pfade, keine Parameter" do
    log =
      capture_log(fn ->
        Logger.error(
          ~s(INSERT Geheimtext /Users/jemand/Library/ratsprojekte.db %{"titel" => "Antrag"})
        )
      end)

    assert log =~ "Ereignis ohne Inhalt"
    refute log =~ "Geheimtext"
    refute log =~ "/Users/"
    refute log =~ "Antrag"
  end

  test "provozierter Absturz: der Crash-Report trägt weder Zustand noch Nachricht" do
    log =
      capture_log(fn ->
        {:ok, pid} = Agent.start(fn -> %{eintrag: "Geheimtext aus dem Bestand"} end)
        ref = Process.monitor(pid)
        Agent.cast(pid, fn _state -> raise ArgumentError, "Geheimtext in der Ausnahme" end)
        assert_receive {:DOWN, ^ref, :process, ^pid, _}
        Logger.flush()
      end)

    assert log =~ "Ereignis ohne Inhalt"
    refute log =~ "Geheimtext"
  end
end
