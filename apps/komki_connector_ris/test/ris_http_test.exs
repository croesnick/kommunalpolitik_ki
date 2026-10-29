defmodule KomkiConnectorRis.RisHttpTest do
  use ExUnit.Case, async: true

  alias KomkiConnectorRis.RisHttp

  test "cli laesst den Runner ohne Argumente und im Test weg" do
    refute_runner = fn _argv -> flunk("Runner darf hier nicht laufen") end

    assert RisHttp.cli([], refute_runner) == :ok
    # Unter `mix test` gilt: keine CLI-Ausfuehrung.
    assert RisHttp.cli(["--port", "1"], refute_runner) == :ok
  end

  test "cli ruft den Runner mit :force" do
    assert RisHttp.cli(["--port", "1"], fn argv -> {:gestartet, argv} end, true) ==
             {:gestartet, ["--port", "1"]}
  end
end
