defmodule RatsprojekteWeb.ContentSecurityPolicyTest do
  # CSP zurückgetragen aus dem alten Bestand (#435, ursprünglich #150/#151).
  # Die Policy ist Regel, kein Ausrüstungsgegenstand: Dieser Test prüft sie
  # gegen jede gerenderte Seite — auch dass jedes Inline-Script (das
  # Theme-Script im Root-Layout) von seinem SHA-256-Hash in script-src
  # abgedeckt ist. Ändert sich das Script, schlägt der Test an und der Hash
  # in router.ex (@content_security_policy) muss mitgezogen werden.
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

    for name <-
          ~w(default-src script-src style-src img-src connect-src base-uri form-action frame-ancestors) do
      assert Map.has_key?(policy, name), "missing directive #{name}"
    end
  end

  test "the policy allows only the own origin and no foreign hosts", %{conn: conn} do
    policy = conn |> get(~p"/") |> directives()

    assert policy["default-src"] == ["'self'"]
    assert hd(policy["script-src"]) == "'self'"
    assert policy["connect-src"] == ["'self'"]

    for source <- List.flatten(Map.values(policy)) do
      refute String.starts_with?(source, "//") || String.contains?(source, "://"),
             "#{source} erlaubt eine fremde Herkunft"
    end
  end

  test "every inline script is covered by a hash in script-src", %{conn: conn} do
    conn = get(conn, ~p"/")
    body = html_response(conn, 200)
    policy = directives(conn)

    inline_scripts =
      List.flatten(Regex.scan(~r/<script>(.*?)<\/script>/s, body, capture: :all_but_first))

    assert inline_scripts != [], "erwartet: mindestens ein Inline-Script im Root-Layout"

    for script <- inline_scripts do
      hash = "'sha256-" <> Base.encode64(:crypto.hash(:sha256, script)) <> "'"

      assert hash in policy["script-src"],
             "Inline-Script ist nicht von der CSP abgedeckt: #{hash} fehlt in script-src — Hash in router.ex @content_security_policy mitziehen"
    end
  end

  test "style-src is the only directive that allows 'unsafe-inline'", %{conn: conn} do
    policy = conn |> get(~p"/") |> directives()

    assert "'unsafe-inline'" in policy["style-src"]

    for {name, sources} <- policy, name != "style-src" do
      refute "'unsafe-inline'" in sources, "#{name} must not allow 'unsafe-inline'"
    end
  end
end
