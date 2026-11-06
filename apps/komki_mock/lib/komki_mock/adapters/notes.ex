defmodule KomkiMock.Adapters.Notes do
  @moduledoc """
  The smallest useful adapter: a list of notes. It is the runtime's own
  test subject and the example to copy when writing a real adapter.

      GET  /notes          all notes
      GET  /notes/<id>     one note, 404 if unknown
      POST /notes          {"text": "..."} -> 201 with the new note

  Seeds: `default` (two notes) and `empty`.
  """

  @behaviour KomkiMock.Adapter

  @impl true
  def seed("default") do
    {:ok,
     %{
       "next_id" => 3,
       "notes" => [
         %{"id" => 1, "text" => "Erste Notiz"},
         %{"id" => 2, "text" => "Zweite Notiz"}
       ]
     }}
  end

  def seed("empty"), do: {:ok, %{"next_id" => 1, "notes" => []}}
  def seed(_name), do: :error

  @impl true
  def handle(%{method: "GET", path: "/notes"}, data), do: {json(200, data["notes"]), data}

  def handle(%{method: "GET", path: "/notes/" <> id}, data) do
    case Enum.find(data["notes"], &(Integer.to_string(&1["id"]) == id)) do
      nil -> {json(404, %{"error" => "not found"}), data}
      note -> {json(200, note), data}
    end
  end

  def handle(%{method: "POST", path: "/notes", body: body}, data) do
    case JSON.decode(body) do
      {:ok, %{"text" => text}} when is_binary(text) ->
        note = %{"id" => data["next_id"], "text" => text}
        data = %{data | "next_id" => data["next_id"] + 1, "notes" => data["notes"] ++ [note]}
        {json(201, note), data}

      _ ->
        {json(400, %{"error" => "expected {\"text\": <string>}"}), data}
    end
  end

  def handle(_request, data), do: {json(404, %{"error" => "not found"}), data}

  defp json(status, body),
    do: {status, [{"content-type", "application/json"}], JSON.encode!(body)}
end
