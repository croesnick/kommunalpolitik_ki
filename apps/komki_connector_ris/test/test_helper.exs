# Mock, recorder, ris_cassettes and ris_skeleton (inferred schema) are standalone
# scripts (startable outside the tests too) and are only loaded here.
Code.require_file("../priv/mock_ris.exs", __DIR__)
Code.require_file("../priv/ris_cassettes.exs", __DIR__)
Code.require_file("../priv/ris_recorder.exs", __DIR__)
Code.require_file("../priv/ris_skeleton.exs", __DIR__)
Code.require_file("../priv/ris_struktur.exs", __DIR__)
ExUnit.start(capture_log: true)
