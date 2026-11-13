# elixir scripts/screenshot/test/spec_test.exs

ExUnit.start()
Code.require_file("../spec.exs", __DIR__)

defmodule Screenshot.SpecTest do
  use ExUnit.Case, async: true

  alias Screenshot.Spec

  describe "parse/1" do
    test "routes and navigations with the default themes and widths" do
      assert {:ok, spec} =
               Spec.parse(%{
                 "routes" => ["/", "/stand", "/projekte/radweg-bahnhofstrasse"],
                 "navigations" => [%{"from" => "/", "to" => "/stand"}]
               })

      assert spec.themes == ["light", "dark"]
      assert spec.widths == [390, 1280]
      assert spec.navigations == [{"/", "/stand"}]
      assert length(Spec.shots(spec)) == 3 * 2 * 2 + 1 * 2 * 2
    end

    test "only local paths pass" do
      for route <- [
            "//evil.example/x",
            "http://127.0.0.1/",
            "https://example.com",
            "/stand?x=1",
            "/stand#a",
            "/../etc/passwd",
            "/a/../b",
            "stand",
            "",
            "/a b",
            "/a\nb",
            1
          ] do
        assert {:error, _} = Spec.parse(%{"routes" => [route]}), inspect(route)
        nav = %{"from" => "/", "to" => route}
        assert {:error, _} = Spec.parse(%{"navigations" => [nav]}), inspect(route)
      end
    end

    test "themes, widths and the shot count are bounded" do
      assert {:error, _} = Spec.parse(%{"routes" => ["/"], "themes" => ["sepia"]})
      assert {:error, _} = Spec.parse(%{"routes" => ["/"], "themes" => []})
      assert {:error, _} = Spec.parse(%{"routes" => ["/"], "widths" => [100]})
      assert {:error, _} = Spec.parse(%{"routes" => ["/"], "widths" => [5000]})
      assert {:error, _} = Spec.parse(%{"routes" => ["/"], "widths" => ["390"]})

      many = for i <- 1..11, do: "/r#{i}"
      assert {:error, message} = Spec.parse(%{"routes" => many})
      assert message =~ "höchstens 40"
    end

    test "unknown fields, empty lists and non-objects are refused" do
      assert {:error, message} = Spec.parse(%{"routes" => ["/"], "flags" => ["--no-sandbox"]})
      assert message =~ "flags"
      assert {:error, _} = Spec.parse(%{"routes" => []})
      assert {:error, _} = Spec.parse(%{"navigations" => [%{"from" => "/"}]})

      assert {:error, _} =
               Spec.parse(%{"navigations" => [%{"from" => "/", "to" => "/", "x" => 1}]})

      assert {:error, _} = Spec.parse(["/"])
    end
  end

  test "file names are stable and carry route, theme and width" do
    assert Spec.name({:page, "/", "dark", 390}) == "start-dark-390"
    assert Spec.name({:page, "/projekte/radweg", "light", 1280}) == "projekte_radweg-light-1280"
    assert Spec.name({:navigate, {"/", "/stand"}, "dark", 390}) == "nav-start-nach-stand-dark-390"
  end
end
