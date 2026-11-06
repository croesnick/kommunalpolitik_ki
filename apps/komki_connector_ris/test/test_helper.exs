# The mock, recording proxy, extractors, and generator are standalone
# scripts (startable outside the tests as well) and are only loaded here.
Code.require_file("../priv/gartenstadt_daten.exs", __DIR__)
Code.require_file("../priv/mock_ris.exs", __DIR__)
Code.require_file("../priv/ris_cassettes.exs", __DIR__)
Code.require_file("../priv/ris_ngramm.exs", __DIR__)
Code.require_file("../priv/ris_recorder.exs", __DIR__)
Code.require_file("../priv/ris_gartenstadt.exs", __DIR__)
Code.require_file("../priv/ris_skeleton.exs", __DIR__)
Code.require_file("../priv/ris_struktur.exs", __DIR__)
ExUnit.start(capture_log: true)
