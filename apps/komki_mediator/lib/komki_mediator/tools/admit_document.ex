defmodule KomkiMediator.Tools.AdmitDocument do
  @moduledoc """
  MCP-Tool `admit_document`: ein Raum-Dokument wird zum Agentenkontext
  zugelassen. Der Dateizugriff (der Vollzug) passiert NACH einem Permit —
  vor dem Permit gibt es keinen Blick in die Datei.

  Den Vollzug fuehrt der Dokument-Connector aus (Ticket #169, Manifest
  `documents`): der Vermittler selbst darf die Dokumente nicht lesen.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias KomkiConnector.Manifest
  alias KomkiMediator.{Env, Gate, PDR}
  alias Sidecar.Client

  # Schema und Beschreibung wie im Manifest `documents` (Ticket #169);
  # KomkiMediator.FassungTest haelt beide gleich.
  schema do
    field(:document_id, :string, required: true, max_length: 64, pattern: "^[a-z0-9-]+$")
  end

  @impl true
  def description,
    do:
      "Ein Raumdokument anhand seiner document_id zum Agentenkontext zulassen (z. B. \"doc-oeffentlich\")."

  @impl true
  def execute(params, frame) do
    env = Env.for_call(frame)

    # Der vollstaendige gerenderte Aufruf geht ans Gate (exakter Call als
    # intent_hash-Basis); kuenftige Schema-Felder landen mechanisch mit im
    # Hash. Der Executor ruft den Dokument-Connector.
    executor = fn -> read_document(env, params.document_id) end

    response = Gate.call(env, "admit_document", params, executor)
    {:reply, Response.json(Response.tool(), response), frame}
  end

  @doc false
  @spec read_document(map(), String.t()) :: {:ok, map()} | {:error, term()}
  def read_document(env, document_id) do
    with dir when is_binary(dir) <- Map.get(env, :connectors_dir),
         socket = Path.join(dir, Manifest.fetch!("documents").id <> ".sock"),
         {:ok, %{"content" => content}} <-
           Client.call(socket, PDR.new_id(), "read", %{"document_id" => document_id}) do
      # Objekt-Claim der Antwort (Gate-2-Bindung): das Ergebnis kann dem
      # entschiedenen Dokument-Objekt zugeordnet werden.
      {:ok, %{"object_id" => document_id, "document_id" => document_id, "content" => content}}
    else
      {:error, %{"code" => code}} -> {:error, code}
      nil -> {:error, "kein Connector-Verzeichnis"}
      _other -> {:error, "unerwartete Antwort des Dokument-Connectors"}
    end
  end
end
