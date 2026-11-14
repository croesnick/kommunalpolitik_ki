defmodule KomkiEgress.ConfigTest do
  use ExUnit.Case, async: true

  alias KomkiEgress.{Config, Target}

  test "gültige Konfiguration mit normalisierter Allowlist" do
    line =
      ~s({"ports": {"49601": {"connector": "web", "allow": ["API.Search.Brave.com:443"]},) <>
        ~s( "49602": {"connector": "ris", "allow": ["ris.komuna.net:443", "ris.komuna.net:443"]}}}\n)

    assert {:ok, config} = Config.parse(line)

    assert config == %{
             49_601 => %{connector: "web", allow: MapSet.new(["api.search.brave.com:443"])},
             49_602 => %{connector: "ris", allow: MapSet.new(["ris.komuna.net:443"])}
           }
  end

  @invalid [
    {"", "kein gültiges JSON"},
    {"nicht json", "kein gültiges JSON"},
    {~s([]), "genau ein Objekt"},
    {~s({}), "genau ein Objekt"},
    {~s({"ports": {}}), "leer"},
    {~s({"ports": []}), "genau ein Objekt"},
    {~s({"ports": {}, "extra": 1}), "genau ein Objekt"},
    {~s({"ports": {"abc": {"connector": "web", "allow": ["a.de:443"]}}}), "keine Portnummer"},
    {~s({"ports": {"0": {"connector": "web", "allow": ["a.de:443"]}}}), "keine Portnummer"},
    {~s({"ports": {"70000": {"connector": "web", "allow": ["a.de:443"]}}}), "keine Portnummer"},
    {~s({"ports": {"4960 1": {"connector": "web", "allow": ["a.de:443"]}}}), "keine Portnummer"},
    {~s({"ports": {"49601": {"allow": ["a.de:443"]}}}), "erwartet genau"},
    {~s({"ports": {"49601": {"connector": "web"}}}), "erwartet genau"},
    {~s({"ports": {"49601": {"connector": "web", "allow": []}}}), "erwartet genau"},
    {~s({"ports": {"49601": {"connector": "web", "allow": "a.de:443"}}}), "erwartet genau"},
    {~s({"ports": {"49601": {"connector": "web", "allow": ["a.de:443"], "x": 1}}}),
     "erwartet genau"},
    {~s({"ports": {"49601": {"connector": "Web Connector", "allow": ["a.de:443"]}}}),
     "Connector-Name"},
    {~s({"ports": {"49601": {"connector": "web", "allow": [443]}}}), "kein String"},
    {~s({"ports": {"49601": {"connector": "web", "allow": ["a.de"]}}}), "host:port"},
    {~s({"ports": {"49601": {"connector": "web", "allow": ["a.de:0"]}}}), "host:port"},
    {~s({"ports": {"49601": {"connector": "web", "allow": ["*.a.de:443"]}}}), "host:port"},
    {~s({"ports": {"49601": {"connector": "web", "allow": ["a.de:443/x"]}}}), "host:port"},
    {~s({"ports": {"49601": {"connector": "web", "allow": ["1.2.3.4:443"]}}}), "IP-Literal"},
    {~s({"ports": {"49601": {"connector": "web", "allow": ["[::1]:443"]}}}), "IP-Literal"}
  ]

  test "ungültige Konfigurationen mit klarer Meldung" do
    for {line, fragment} <- @invalid do
      assert {:error, message} = Config.parse(line), line
      assert message =~ fragment, "#{line}: #{message}"
    end
  end

  describe "Target.parse/1" do
    test "Normalform" do
      assert Target.parse("Example.COM:443") == {:ok, {"example.com", 443}}
      assert Target.to_string({"example.com", 443}) == "example.com:443"
    end

    test "IP-Literale, auch Kurzformen" do
      for text <- ["127.0.0.1:443", "127.1:443", "2130706433:443", "[::1]:443", "[fe80::1]:80"] do
        assert Target.parse(text) == {:error, :ip_literal}, text
      end
    end

    test "kaputte Ziele" do
      for text <- ["", ":443", "a.de", "a.de:", "a.de:x", "a.de:65536", "a..de:443", "-a.de:443"] do
        assert Target.parse(text) == {:error, :malformed}, text
      end
    end
  end
end
