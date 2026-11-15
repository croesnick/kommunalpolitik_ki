defmodule RatsprojekteWeb.ZugangTest do
  # Switches the lock on for the whole app, hence not async.
  use RatsprojekteWeb.ConnCase, async: false

  import Ratsprojekte.Betrieb

  alias Ratsprojekte.{Ort, Sperre}

  setup context do
    Application.put_env(:ratsprojekte, :sperre, true)
    on_exit(fn -> Application.delete_env(:ratsprojekte, :sperre) end)
    home = home!()
    eingerichtet!(home)
    provider = aufzeichner(home, reason: "ratsprojekte entsperren", warten: context[:bremsen])
    %{home: home, sperre: sperre!(home, name: Sperre, provider: provider)}
  end

  defp gesperrt?(conn) do
    html = html_response(conn, 401)
    html =~ ~s(id="gesperrt") and html =~ ~s(id="entsperren")
  end

  test "ohne Cookie nur die Sperrseite mit „Entsperren“", %{conn: conn} do
    assert conn |> get(~p"/") |> gesperrt?()
  end

  describe "einmaliger Link (ratsprojekte open)" do
    test "setzt das Cookie, danach ist die Oberfläche offen", %{conn: conn} do
      {:ok, token} = Sperre.oeffnen("111222")

      conn = get(conn, ~p"/zugang/#{token}")
      assert redirected_to(conn) == ~p"/"

      conn = conn |> recycle() |> get(~p"/")
      assert html_response(conn, 200) =~ ~s(id="neue-idee")

      # The link is used up; another browser gets nothing with it.
      assert build_conn() |> get(~p"/zugang/#{token}") |> gesperrt?()
    end

    test "nach dem Sperren hilft das alte Cookie nicht mehr", %{conn: conn} do
      {:ok, token} = Sperre.oeffnen("111222")
      conn = get(conn, ~p"/zugang/#{token}")
      :ok = Sperre.sperren()

      assert conn |> recycle() |> get(~p"/") |> gesperrt?()
    end

    test "Link eines gesperrten Hubs wird nicht eingelöst", %{conn: conn} do
      conn = get(conn, ~p"/zugang/ausgedacht")
      assert gesperrt?(conn)
      assert html_response(conn, 401) =~ "abgelaufen oder schon benutzt"
    end
  end

  describe "Schaltfläche „Entsperren“" do
    test "entsperrt mit Touch ID und öffnet denselben Tab", %{conn: conn} do
      conn = post(conn, ~p"/entsperren", %{"pruefcode" => "111222"})
      assert redirected_to(conn) == ~p"/"
      assert Sperre.status() == :offen

      conn = conn |> recycle() |> get(~p"/")
      assert html_response(conn, 200) =~ ~s(id="neue-idee")
    end

    test "Touch ID abgelehnt oder Schlüssel fehlt: bleibt gesperrt, sagt warum", %{
      conn: conn,
      home: home
    } do
      File.rm!(Ort.schluessel(home))

      conn = post(conn, ~p"/entsperren", %{"pruefcode" => "111222"})
      assert gesperrt?(conn)
      assert html_response(conn, 401) =~ ~s(id="entsperren-fehler")
      assert Sperre.status() == :gesperrt
    end

    # Like a browser: CSRF check on (ConnTest skips it), page reloaded
    # before the click. Regression: the gate cleared the session including
    # the CSRF token, and the click ended in 403.
    test "mit echter CSRF-Prüfung, auch nach Neuladen der Sperrseite", %{conn: conn} do
      conn = get(conn, ~p"/")
      conn = conn |> recycle() |> get(~p"/")
      html = html_response(conn, 401)
      [_, token] = Regex.run(~r/name="_csrf_token"[^>]*value="([^"]+)"/, html)
      [code] = Regex.run(~r/id="pruefcode"[^>]*>(\d{6})</, html, capture: :all_but_first)

      conn =
        conn
        |> recycle()
        |> Plug.Conn.put_private(:plug_skip_csrf_protection, false)
        |> post(~p"/entsperren", %{"_csrf_token" => token, "pruefcode" => code})

      assert redirected_to(conn) == ~p"/"
      assert Sperre.status() == :offen
    end

    test "zweiter Browser bei offenem Hub: neue Abfrage, gleiche Sitzung", %{conn: conn} do
      {:ok, token} = Sperre.oeffnen("111222")
      {:ok, marker} = Sperre.einloesen(token)

      conn = post(conn, ~p"/entsperren", %{"pruefcode" => "111222"})
      assert get_session(conn, :zugang) == marker
    end

    # F21 (#490): Der Touch-ID-Dialog ist zurechenbar, wenn sein Grund den
    # Prüfcode der anfragenden Seite nennt; die Sperrseite zeigt denselben.
    test "Sperrseite zeigt den Prüfcode, der Dialog-Grund trägt ihn", %{conn: conn} do
      html = conn |> get(~p"/") |> html_response(401)
      assert html =~ ~s(id="pruefcode")
      [code] = Regex.run(~r/id="pruefcode"[^>]*>(\d{6})</, html, capture: :all_but_first)

      assert conn |> post(~p"/entsperren", %{"pruefcode" => code}) |> redirected_to() == ~p"/"
      assert_received {:agree, opts}
      assert opts[:reason] =~ code
      assert Sperre.status() == :offen
    end

    @tag :bremsen
    test "läuft schon eine Entsperr-Anfrage: klare Ansage statt zweitem Dialog", %{conn: conn} do
      erste = Task.async(fn -> Sperre.oeffnen("111222") end)
      assert_receive {:agree, _}

      conn = post(conn, ~p"/entsperren", %{"pruefcode" => "222333"})
      assert gesperrt?(conn)
      assert html_response(conn, 401) =~ "läuft schon eine Entsperr-Anfrage"

      send(erste.pid, :freigabe)
      assert {:ok, _} = Task.await(erste, 10_000)
    end
  end
end
