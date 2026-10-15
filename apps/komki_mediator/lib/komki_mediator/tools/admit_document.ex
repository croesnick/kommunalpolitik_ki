defmodule KomkiMediator.Tools.AdmitDocument do
  @moduledoc """
  MCP-Tool `admit_document`: ein Raum-Dokument wird zum Agentenkontext
  zugelassen. Der Dateizugriff (der Vollzug) passiert NACH einem Permit —
  vor dem Permit gibt es keinen Blick in die Datei.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias KomkiMediator.{Env, Gate}

  schema do
    field(:document_id, :string,
      required: true,
      description: "Objekt-ID des Raumdokuments (z. B. \"doc-oeffentlich\")"
    )
  end

  @impl true
  def execute(params, frame) do
    env = Env.fetch()

    # Der vollstaendige gerenderte Aufruf geht ans Gate (exakter Call als
    # intent_hash-Basis); kuenftige Schema-Felder landen mechanisch mit im
    # Hash. Der Executor liest direkt hier.
    executor = fn ->
      path = Path.join(env.room.documents_dir, params.document_id <> ".md")

      case File.read(path) do
        {:ok, content} ->
          # Objekt-Claim der Antwort (Gate-2-Bindung): das Ergebnis kann
          # dem entschiedenen Dokument-Objekt zugeordnet werden.
          {:ok,
           %{
             "object_id" => params.document_id,
             "document_id" => params.document_id,
             "content" => content
           }}

        {:error, reason} ->
          {:error, reason}
      end
    end

    response = Gate.call(env, "admit_document", params, executor)
    {:reply, Response.json(Response.tool(), response), frame}
  end
end
