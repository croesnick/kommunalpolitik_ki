defmodule KomkiMediator.Templates do
  @moduledoc """
  Default-Raumaufstellung als Elixir-Maps: Registry (Gamma), Raum und die
  drei Beispieldokumente. Ausgegeben wird ueber `KomkiPolicy.JSON.canonical`
  — der Provisionierungs-Output ist damit von Haus aus kanonisch.

  provision!/1 ist idempotent: sobald `registry.json` existiert, wird
  NICHTS mehr ueberschrieben — ein nachtraeglich redigierter Raum bleibt
  genau so, wie die nutzende Person ihn hinterlassen hat.
  """

  alias KomkiPolicy.JSON

  @mediator_dir "mediator"

  @doc "Registry-Term des Default-Arbeitsraums (Gamma der Aufstellung)."
  def registry do
    %{
      "schema" => "komki-registry/1",
      "registry_id" => "reg-komki-arbeitsraum",
      "observers" => ["nutzende-person", "pi-agent"],
      "fact_fields" => %{
        "purpose" => "string",
        "vertraulich_freigabe" => "boolean"
      },
      "environments" => %{
        "lokaler-arbeitsraum@1" => %{"observers" => ["nutzende-person", "pi-agent"]}
      },
      "bindings" => %{
        "mediator-ping@1" => %{
          "readers" => ["nutzende-person", "pi-agent"],
          "operations" => %{"admit" => true},
          "relaxation_authorities" => []
        },
        "doc-oeffentlich@1" => %{
          "readers" => ["nutzende-person", "pi-agent"],
          "operations" => %{"admit" => true},
          "relaxation_authorities" => []
        },
        "doc-vertraulich@1" => %{
          "readers" => ["nutzende-person", "pi-agent"],
          "operations" => %{"admit" => %{"eq" => ["purpose", "vertraulich"]}},
          "relaxation_authorities" => []
        },
        "doc-pending-freigabe@1" => %{
          "readers" => ["nutzende-person", "pi-agent"],
          "operations" => %{"admit" => %{"eq" => ["vertraulich_freigabe", true]}},
          "relaxation_authorities" => ["nutzende-person"]
        }
      }
    }
  end

  @doc """
  Raum-Term des Default-Arbeitsraums. Bewusst OHNE die
  `vertraulich_freigabe`-Fakt: `doc-pending-freigabe` faehrt damit die
  indeterminate-Route (missing_fact) — die Freigabe ist nachzuholen.
  """
  def room do
    %{
      "schema" => "komki-mediator-room/1",
      "identity" => "pi-agent",
      "workspace_id" => "ws-komki-arbeitsraum",
      "environment" => "lokaler-arbeitsraum@1",
      "documents_dir" => "documents",
      "facts" => %{
        "audit_path_ready" => %{
          "value" => true,
          "source" => "journal-verwaltung",
          "source_kind" => "technical"
        },
        "environment_observers_complete" => %{
          "value" => true,
          "source" => "umgebungs-verwaltung",
          "source_kind" => "assumption"
        },
        "has_object_access_right" => %{
          "value" => true,
          "source" => "objekt-verwaltung",
          "source_kind" => "administered"
        },
        "has_operation_right" => %{
          "value" => true,
          "source" => "rechte-verwaltung",
          "source_kind" => "administered"
        },
        "purpose" => %{
          "value" => "offene-recherche",
          "source" => "auftrags-verwaltung",
          "source_kind" => "administered"
        }
      },
      "objects" => %{
        "mediator-ping" => %{"version" => "v1", "labels" => ["mediator-ping@1"]},
        "doc-oeffentlich" => %{"version" => "v1", "labels" => ["doc-oeffentlich@1"]},
        "doc-vertraulich" => %{"version" => "v1", "labels" => ["doc-vertraulich@1"]},
        "doc-pending-freigabe" => %{
          "version" => "v1",
          "labels" => ["doc-pending-freigabe@1"]
        }
      }
    }
  end

  @doc "Kurzer deutscher Beispielinhalt fuer eines der drei Raumdokumente."
  @spec document_content(String.t()) :: String.t()
  def document_content("doc-oeffentlich") do
    ~S(# Offentliche Notiz
Diese Notiz ist allgemein zugaenglich.
Sie ist fur jede offene Recherche im Arbeitsraum freigegeben.
)
  end

  def document_content("doc-vertraulich") do
    ~S(# Vertrauliche Notiz
Diese Notiz dient dem vertraulichen Zweck.
Sie ist nur mit dem passenden Zweck-Fakt zulaessig.
)
  end

  def document_content("doc-pending-freigabe") do
    ~S(# Notiz in Freigabe-Pause
Diese Notiz wartet auf die vertraulich_freigabe.
Ohne Freigabe trennt das Gate den Inhalt zurueck.
)
  end

  @doc "Provisioniert `<base>/mediator/` nur, wenn keine `registry.json` vorliegt."
  def provision!(base_dir) do
    mediator_dir = Path.join(base_dir, @mediator_dir)
    registry_path = Path.join(mediator_dir, "registry.json")

    if File.exists?(registry_path) do
      :already_provisioned
    else
      documents_dir = Path.join(mediator_dir, room()["documents_dir"])
      File.mkdir_p!(documents_dir)
      File.write!(registry_path, JSON.canonical(registry()))
      File.write!(Path.join(mediator_dir, "room.json"), JSON.canonical(room()))
      write_documents(documents_dir)
      :ok
    end
  end

  defp write_documents(documents_dir) do
    for document_id <- ["doc-oeffentlich", "doc-vertraulich", "doc-pending-freigabe"] do
      path = Path.join(documents_dir, document_id <> ".md")
      File.write!(path, document_content(document_id))
    end

    :ok
  end
end
