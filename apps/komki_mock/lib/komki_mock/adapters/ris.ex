defmodule KomkiMock.Adapters.Ris do
  @moduledoc """
  The guest endpoints of the RIS API (`risapi1.komuna.net/web/`), the ones
  `apps/komki_connector_ris` speaks, rendered from the data:

      GET /guestmeetings                     {"items": [meeting, ...]}
      GET /guestmeetings/<id>                meeting with its public and protected part
      GET /guestagendaitems/<meeting-item>   agenda item with its text block (Base64 HTML)

  Other methods answer 405, other paths 404. The time window (`from`,
  `until`) is ignored and every meeting is listed, so fixed seed dates never
  age out of the connector's window.

  Unlike the real guest API the mock serves non-public items with their
  text: filtering is the connector's job, not the mock's.

  Data: `{"meetings": [{"id", "name", "committee", "date", "tops": [{"id",
  "nr", "name", "restricted", "protected", "text"}]}]}`; `protected` is
  optional and puts the item into the protected part of its meeting. Seeds
  are JSON files in `priv/seeds/ris/<name>.json`.

  The `default` seed is a test fixture with intent:

  - "Bahnhofstraße" appears in two public items (once in the title, once
    only in the text) and in two non-public ones: 1001-2 (`restricted` in
    the public part) and 1002-3 (not restricted, but in the protected
    part). That is the counting test.
  - "Flurstück" appears only in the non-public item 1001-2.
  - Item 1001-3 carries a prompt injection in its public text.
  """

  @behaviour KomkiMock.Adapter

  @impl true
  def seed(name), do: KomkiMock.Seeds.load("ris", name)

  @impl true
  def handle(%{method: "GET", path: path}, data),
    do: {route(String.split(path, "/", trim: true), data["meetings"]), data}

  def handle(_request, data), do: {json(405, %{"error" => "method not allowed"}), data}

  defp route(["guestmeetings"], meetings),
    do: json(200, %{"items" => Enum.map(meetings, &meeting_summary/1)})

  defp route(["guestmeetings", id], meetings),
    do: found(Enum.find(meetings, &(Integer.to_string(&1["id"]) == id)), &meeting_detail/1)

  defp route(["guestagendaitems", id], meetings),
    do:
      found(
        Enum.find_value(meetings, &Enum.find(&1["tops"], fn t -> t["id"] == id end)),
        &top_detail/1
      )

  defp route(_path, _meetings), do: json(404, %{"error" => "not found"})

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

  defp top_detail(t) do
    [meeting_id | _] = String.split(t["id"], "-")

    %{
      "id" => t["id"],
      "numbering" => t["nr"],
      "name" => t["name"],
      "restricted" => t["restricted"],
      "textsanddocsvisible" => true,
      "meetingid" => String.to_integer(meeting_id),
      "textblocks" => [
        %{"caption" => "Sachverhalt", "content" => Base.encode64("<p>" <> t["text"] <> "</p>")}
      ],
      "documents" => []
    }
  end

  defp json(status, body),
    do: {status, [{"content-type", "application/json"}], JSON.encode!(body)}
end
