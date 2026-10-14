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

    # Kanonisch gerendeter Aufruf: String-Schluessel sind der Vertrag
    # zwischen MCP-Schicht und Gate (intent_hash).
    gate_params = %{"document_id" => params.document_id}

    executor = fn ->
      path = Path.join(env.room.documents_dir, gate_params["document_id"] <> ".md")

      case File.read(path) do
        {:ok, content} ->
          {:ok, %{"document_id" => gate_params["document_id"], "content" => content}}

        {:error, reason} ->
          {:error, reason}
      end
    end

    response = Gate.call(env, "admit_document", gate_params, executor)
    {:reply, Response.json(Response.tool(), response), frame}
  end
end
