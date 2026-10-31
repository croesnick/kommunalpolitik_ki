# Mock, Aufzeichnungs-Proxy und Skelett-Extraktor sind eigenstaendige Skripte
# (auch ausserhalb der Tests startbar) und werden hier nur geladen.
Code.require_file("../priv/mock_ris.exs", __DIR__)
Code.require_file("../priv/ris_kassetten.exs", __DIR__)
Code.require_file("../priv/ris_recorder.exs", __DIR__)
Code.require_file("../priv/ris_skeleton.exs", __DIR__)
ExUnit.start(capture_log: true)
