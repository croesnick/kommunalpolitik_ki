defmodule KomkiMediator.Templates do
  @moduledoc """
  Default-Raumaufstellung als Elixir-Maps: Registry (Gamma), Raum und die
  drei Beispieldokumente. Die Registry traegt zusaetzlich die
  Γ-Konventionen des Connector-Vertrags §7 (Beobachter, Umgebungen,
  Connector-Bindungen, Fakt `output_content_digest`); der Default-Raum ist
  der Referenzraum **recherche**. Ausgegeben wird ueber `KomkiPolicy.JSON.canonical`
  — der Provisionierungs-Output ist damit von Haus aus kanonisch.

  provision!/1 ist idempotent: sobald `registry.json` existiert, wird
  nichts ueberschrieben, was die nutzende Person veraendert haben koennte.
  Einzige Ausnahme (Ticket #177): Sind `registry.json` und `room.json`
  byte-genau eine fruehere Fassung dieser Vorlagen (SHA-256 in
  `@outdated`), ersetzt provision!/1 sie durch die aktuelle. Eine Sicherung
  entfaellt bewusst: der Inhalt einer unveraenderten Vorlage steht
  vollstaendig im Git-Verlauf, und das Seatbelt-Profil des Vermittlers
  erlaubt nur genau diese beiden Dateinamen. Ist nur eine der beiden Dateien
  eine alte Vorlage, die andere aber veraendert, bricht provision!/1 mit
  Erklaerung ab, statt zu raten.

  Pflege: Wer `registry/0` oder `room/0` aendert, traegt die bisherigen
  Hashes aus `@current` in `@outdated` ein und setzt `@current` neu; ein
  Test haelt `@current` an den tatsaechlichen Vorlagen fest.
  """

  alias KomkiPolicy.JSON

  @mediator_dir "mediator"

  # SHA-256 der kanonischen Vorlagen. @outdated: fruehere Fassungen auf main
  # (#106 und #107 fuer die Registry, beide mit demselben Raum).
  @current %{
    "registry.json" => "38e86ed685b8887ddac4eb1976873b105fb1f272ce6c8ff67ac806370c8ecdf7",
    "room.json" => "4b3ac34dc5ac6a81ea5cb81178cd1fea9f0045e753a079823aab98f6ea45fe32"
  }
  @outdated %{
    "registry.json" => [
      "fed48d30194094c6e84be239ef40bf74be88457b1aaec09cb3dce8b5bb090e4f",
      "d2b6a4e987036711a517a31dc40368dea82f7136b4213fbf9614cf290ba6d22f"
    ],
    "room.json" => ["127831a737e7f5565d8def234c260ca270056b8954b346725f03ef638ef0b51f"]
  }

  @observers ["brave-search", "nutzende-person", "pi-agent", "ris-betreiber"]

  @doc "Registry-Term des Default-Arbeitsraums (Gamma der Aufstellung)."
  def registry do
    %{
      "schema" => "komki-registry/2",
      "registry_id" => "reg-komki-arbeitsraum",
      "observers" => @observers,
      "fact_fields" => %{
        "output_content_digest" => "string",
        "purpose" => "string",
        "vertraulich_freigabe" => "boolean"
      },
      "environments" => %{
        "lokaler-arbeitsraum@1" => %{"observers" => ["nutzende-person", "pi-agent"]},
        "ris-abruf@1" => %{"observers" => ["nutzende-person", "pi-agent", "ris-betreiber"]},
        "vault-lokal@1" => %{"observers" => ["nutzende-person", "pi-agent"]},
        "web-suche@1" => %{"observers" => ["brave-search", "nutzende-person", "pi-agent"]}
      },
      "bindings" =>
        Map.merge(connector_bindings(), %{
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
        })
    }
  end

  # Connector-Bindungen (Connector-Vertrag §7): admit und emit ohne
  # Bedingung. Die Trennung leistet der Empfaengerkreis: vault-vertraulich
  # liest nur nutzende-person und pi-agent, damit faellt in einem Raum mit
  # dieser Bindung jede Anfrage an RIS oder Websuche an recipient_inclusion.
  defp connector_bindings do
    open = %{"operations" => %{"admit" => true, "emit" => true}, "relaxation_authorities" => []}

    %{
      "ris-oeffentlich@1" => Map.put(open, "readers", @observers),
      "web-oeffentlich@1" => Map.put(open, "readers", @observers),
      "vault-oeffentlich@1" => Map.put(open, "readers", @observers),
      "vault-vertraulich@1" => Map.put(open, "readers", ["nutzende-person", "pi-agent"])
    }
  end

  @doc "B_W des Referenzraums recherche (Default-Raum)."
  @spec recherche_bindings() :: [String.t()]
  def recherche_bindings, do: ["ris-oeffentlich@1", "vault-oeffentlich@1", "web-oeffentlich@1"]

  @doc "B_W des Referenzraums vertraulich (Connector-Vertrag §7)."
  @spec vertraulich_bindings() :: [String.t()]
  def vertraulich_bindings,
    do: ["ris-oeffentlich@1", "vault-oeffentlich@1", "vault-vertraulich@1", "web-oeffentlich@1"]

  @doc """
  Raum-Term des Default-Arbeitsraums. Bewusst OHNE die
  `vertraulich_freigabe`-Fakt: `doc-pending-freigabe` faehrt damit die
  indeterminate-Route (missing_fact) — die Freigabe ist nachzuholen.
  `workspace_bindings` ist B_W des Referenzraums recherche.
  """
  def room do
    %{
      "schema" => "komki-mediator-room/1",
      "identity" => "pi-agent",
      "workspace_id" => "ws-komki-arbeitsraum",
      "environment" => "lokaler-arbeitsraum@1",
      "documents_dir" => "documents",
      "workspace_bindings" => recherche_bindings(),
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

  @doc "Gepinnte SHA-256 der aktuellen Vorlagen (fuer den Pflege-Test)."
  def current_hashes, do: @current

  @doc """
  Provisioniert `<base>/mediator/`: legt die Vorlagen an, wenn keine
  `registry.json` vorliegt, und ersetzt unveraenderte fruehere Fassungen
  (Ticket #177). Ergebnis: `:ok` (neu angelegt), `:already_provisioned`,
  `{:migrated, from}` (alte Vorlagen ersetzt) oder `{:error, detail}`.
  """
  def provision!(base_dir) do
    mediator_dir = Path.join(base_dir, @mediator_dir)
    registry_path = Path.join(mediator_dir, "registry.json")

    if File.exists?(registry_path) do
      migrate(mediator_dir)
    else
      write_templates(mediator_dir)
      :ok
    end
  end

  defp migrate(mediator_dir) do
    states = Map.new(["registry.json", "room.json"], &{&1, state(mediator_dir, &1)})

    cond do
      Enum.all?(states, fn {_file, state} -> state == :outdated end) ->
        write_templates(mediator_dir)
        {:migrated, "unveraenderte Vorlagen einer frueheren Fassung"}

      Enum.any?(states, fn {_file, state} -> state == :outdated end) ->
        {:error,
         "registry.json und room.json passen nicht zusammen: " <>
           describe(states) <>
           ". komki ersetzt nur unveraenderte alte Vorlagen. Eigene Aenderungen sichern, " <>
           "beide Dateien aus " <>
           mediator_dir <> " entfernen; der naechste Start legt die neuen Vorlagen an."}

      true ->
        :already_provisioned
    end
  end

  defp state(dir, file) do
    case File.read(Path.join(dir, file)) do
      {:ok, raw} ->
        hash = Base.encode16(:crypto.hash(:sha256, raw), case: :lower)

        cond do
          hash == @current[file] -> :current
          hash in @outdated[file] -> :outdated
          true -> :own
        end

      {:error, _} ->
        :own
    end
  end

  defp describe(states) do
    Enum.map_join(states, ", ", fn
      {file, :outdated} -> file <> " ist eine unveraenderte alte Vorlage"
      {file, :current} -> file <> " ist aktuell"
      {file, :own} -> file <> " wurde veraendert"
    end)
  end

  # Dokumente nur anlegen, wenn sie fehlen: vorhandene bleiben unberuehrt.
  defp write_templates(mediator_dir) do
    documents_dir = Path.join(mediator_dir, room()["documents_dir"])
    File.mkdir_p!(documents_dir)
    File.write!(Path.join(mediator_dir, "registry.json"), JSON.canonical(registry()))
    File.write!(Path.join(mediator_dir, "room.json"), JSON.canonical(room()))
    write_documents(documents_dir)
  end

  defp write_documents(documents_dir) do
    for document_id <- ["doc-oeffentlich", "doc-vertraulich", "doc-pending-freigabe"],
        path = Path.join(documents_dir, document_id <> ".md"),
        not File.exists?(path) do
      File.write!(path, document_content(document_id))
    end

    :ok
  end
end
