# Der Mock ist ein eigenstaendiges Skript (auch ausserhalb der Tests
# startbar) und wird hier nur geladen, nicht gestartet.
Code.require_file("../priv/mock_ris.exs", __DIR__)
ExUnit.start(capture_log: true)
