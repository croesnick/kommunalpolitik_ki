defmodule KomkiMediator.Tools.ListDocuments do
  @moduledoc """
  MCP-Tool `list_documents` (Ticket #218): pi erfaehrt, welche
  Raumdokumente es mit `admit_document` zulassen kann, ohne Inhalte zu
  sehen. Entscheidung und PDR in `KomkiMediator.Gate.list_documents/1`.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias KomkiMediator.{Env, Gate}

  schema do
  end

  @impl true
  def description,
    do:
      "Die Raumdokumente auflisten, die du mit admit_document lesen kannst: document_id und Labels, keine Inhalte."

  @impl true
  def execute(_params, frame) do
    response = Gate.list_documents(Env.for_call(frame))
    {:reply, Response.json(Response.tool(), response), frame}
  end
end
