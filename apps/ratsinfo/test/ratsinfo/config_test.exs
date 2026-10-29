defmodule Ratsinfo.ConfigTest do
  # Nicht async: RIS_BASE_URL ist prozessweit.
  use ExUnit.Case, async: false

  alias Ratsinfo.Config

  setup do
    previous = System.get_env("RIS_BASE_URL")

    on_exit(fn ->
      if previous,
        do: System.put_env("RIS_BASE_URL", previous),
        else: System.delete_env("RIS_BASE_URL")
    end)
  end

  test "ohne RIS_BASE_URL gilt das echte RIS" do
    System.delete_env("RIS_BASE_URL")
    assert Config.base_url() == "https://risapi1.komuna.net/web/"
  end

  test "RIS_BASE_URL auf Loopback, fehlender Schraegstrich wird ergaenzt" do
    System.put_env("RIS_BASE_URL", "http://127.0.0.1:4020")
    assert Config.base_url() == "http://127.0.0.1:4020/"

    System.put_env("RIS_BASE_URL", "http://localhost:4010/")
    assert Config.base_url() == "http://localhost:4010/"
  end

  test "RIS_BASE_URL auf fremde Hosts wird abgewiesen (Zugangsdaten gingen mit)" do
    for url <- ["https://example.org/", "http://127.0.0.1.example.org/", "file:///tmp"] do
      System.put_env("RIS_BASE_URL", url)
      assert_raise ArgumentError, ~r/Loopback/, fn -> Config.base_url() end
    end
  end
end
