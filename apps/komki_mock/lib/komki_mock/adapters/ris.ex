defmodule KomkiMock.Adapters.Ris do
  @moduledoc """
  The endpoints of the RIS API (`risapi3.komuna.net/web/`) that
  `apps/komki_connector_ris` speaks, rendered from the data:

      GET  /guestmeetings                     {"items": [meeting, ...]}
      GET  /guestmeetings/<id>                meeting with its public and protected part
      GET  /guestagendaitems/<meeting-item>   agenda item with its text block (Base64 HTML)
      POST /auth                              {"login", "password"} -> {"token"}
      GET  /meetings/<id>                     as /guestmeetings/<id>, needs the token
      GET  /agendaitems/<meeting-item>        as /guestagendaitems/<id>, needs the token

  The signed-in endpoints answer 401 without `authorization: Bearer
  <token>`; `/auth` answers 401 unless login and password match the seed's
  `account`. Other methods answer 405, other paths 404. The time window
  (`from`, `until`) is ignored and every meeting is listed, so fixed seed
  dates never age out of the connector's window.

  Unlike the real guest API the mock serves non-public items with their
  text: filtering is the connector's job, not the mock's. Like the real
  API, the guest endpoint can withhold the text: with `"guest_texts":
  false` in the data its agenda items carry no text blocks, and only the
  signed-in endpoint has them.

  Data: `{"account": {"login", "password", "token"}, "guest_texts",
  "meetings": [{"id", "name", "committee", "date", "tops": [{"id", "nr",
  "name", "restricted", "protected", "text"}]}]}`; `protected` is optional
  and puts the item into the protected part of its meeting, `guest_texts`
  defaults to true. Seeds are JSON files in `priv/seeds/ris/<name>.json`.

  The `default` seed is a test fixture with intent:

  - "Bahnhofstraße" appears in two public items (once in the title, once
    only in the text) and in two non-public ones: 1001-2 (`restricted` in
    the public part) and 1002-3 (not restricted, but in the protected
    part). That is the counting test.
  - "Flurstück" appears only in the non-public item 1001-2.
  - Item 1001-3 carries a prompt injection in its public text.
  - Its `account` is synthetic; `komki up` hands exactly these values to
    the connector when it runs against the mock
    (`KomkiCli.Connectors.mock_ris_zugang/0`), never the real RIS login.
  """

  @behaviour KomkiMock.Adapter

  @impl true
  def seed(name), do: KomkiMock.Seeds.load("ris", name)

  @impl true
  def handle(%{method: "POST", path: "/auth", body: body}, data),
    do: {auth(body, data["account"]), data}

  def handle(%{method: "GET", path: path} = request, data) do
    signed_in? = signed_in?(request, data["account"])
    {route(String.split(path, "/", trim: true), data, signed_in?), data}
  end

  def handle(_request, data), do: {json(405, %{"error" => "method not allowed"}), data}

  defp auth(body, %{"login" => login, "password" => password, "token" => token}) do
    case JSON.decode(body) do
      {:ok, %{"login" => ^login, "password" => ^password}} -> json(200, %{"token" => token})
      _ -> unauthorized()
    end
  end

  defp auth(_body, _account), do: unauthorized()

  defp signed_in?(%{headers: headers}, %{"token" => token}),
    do: {"authorization", "Bearer " <> token} in headers

  defp signed_in?(_request, _account), do: false

  defp route(["guestmeetings"], data, _signed_in?),
    do: json(200, %{"items" => Enum.map(data["meetings"], &meeting_summary/1)})

  defp route(["guestmeetings", id], data, _signed_in?), do: meeting(data, id)
  defp route(["guestagendaitems", id], data, _signed_in?), do: item(data, id, guest_texts?(data))
  defp route(["meetings", id], data, true), do: meeting(data, id)
  defp route(["agendaitems", id], data, true), do: item(data, id, true)

  defp route([resource, _id], _data, false) when resource in ~w(meetings agendaitems),
    do: unauthorized()

  defp route(_path, _data, _signed_in?), do: json(404, %{"error" => "not found"})

  defp guest_texts?(data), do: Map.get(data, "guest_texts", true) != false

  defp meeting(data, id),
    do:
      found(
        Enum.find(data["meetings"], &(Integer.to_string(&1["id"]) == id)),
        &meeting_detail/1
      )

  defp item(data, id, texts?),
    do:
      found(
        Enum.find_value(data["meetings"], &Enum.find(&1["tops"], fn t -> t["id"] == id end)),
        &top_detail(&1, texts?)
      )

  defp found(nil, _render), do: json(404, %{"error" => "not found"})
  defp found(value, render), do: json(200, render.(value))

  defp meeting_summary(m) do
    %{
      "id" => m["id"],
      "name" => m["name"],
      "meetingdate" => m["date"],
      "committeename" => m["committee"],
      "locationname" => "Rathaus Buchloe, Sitzungssaal",
      "clientid" => 32,
      "clientname" => "Stadt Buchloe",
      "state" => 1
    }
  end

  defp meeting_detail(m) do
    parts =
      for protected <- [false, true] do
        items =
          for t <- m["tops"], Map.get(t, "protected", false) == protected do
            %{
              "id" => t["id"],
              "numbering" => t["nr"],
              "name" => t["name"],
              "restricted" => t["restricted"]
            }
          end

        %{"protectedpart" => protected, "agendaitems" => items}
      end

    Map.put(meeting_summary(m), "parts", parts)
  end

  defp top_detail(t, texts?) do
    [meeting_id | _] = String.split(t["id"], "-")

    %{
      "id" => t["id"],
      "numbering" => t["nr"],
      "name" => t["name"],
      "restricted" => t["restricted"],
      "textsanddocsvisible" => texts?,
      "meetingid" => String.to_integer(meeting_id),
      "textblocks" => if(texts?, do: [text_block(t)], else: []),
      "documents" => []
    }
  end

  defp text_block(t),
    do: %{"caption" => "Sachverhalt", "content" => Base.encode64("<p>" <> t["text"] <> "</p>")}

  defp unauthorized, do: json(401, %{"error" => "unauthorized"})

  defp json(status, body),
    do: {status, [{"content-type", "application/json"}], JSON.encode!(body)}
end
