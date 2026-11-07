defmodule RatsprojekteWeb.ContentSecurityPolicyTest do
  use RatsprojekteWeb.ConnCase, async: true

  defp directives(conn) do
    [csp] = get_resp_header(conn, "content-security-policy")

    Map.new(String.split(csp, ";", trim: true), fn directive ->
      [name | sources] = directive |> String.trim() |> String.split(" ")
      {name, sources}
    end)
  end

  test "browser routes send a CSP with all required directives", %{conn: conn} do
    policy = conn |> get(~p"/") |> directives()

    for name <- ~w(default-src script-src style-src img-src connect-src) do
      assert Map.has_key?(policy, name), "missing directive #{name}"
    end
  end

  test "the policy allows only the own origin and no foreign hosts", %{conn: conn} do
    policy = conn |> get(~p"/") |> directives()

    assert policy["default-src"] == ["'self'"]
    assert policy["script-src"] == ["'self'"]
    assert policy["connect-src"] == ["'self'"]

    refute policy |> Map.values() |> List.flatten() |> Enum.any?(&String.contains?(&1, "//"))
  end

  test "style-src is the only directive that allows 'unsafe-inline'", %{conn: conn} do
    policy = conn |> get(~p"/") |> directives()

    assert "'unsafe-inline'" in policy["style-src"]

    for {name, sources} <- policy, name != "style-src" do
      refute "'unsafe-inline'" in sources, "#{name} must not allow 'unsafe-inline'"
    end
  end
end
