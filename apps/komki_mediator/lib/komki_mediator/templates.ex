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
  Einzige Ausnahme (Ticket #177): Ist `registry.json` oder `room.json`
  byte-genau eine fruehere Fassung dieser Vorlagen (SHA-256 in
  `@outdated`), ersetzt provision!/1 diese Datei durch die aktuelle. Seit
  #208 entscheidet das je Datei: `registry.json` ist der Export des
  Label-Store (`label_store_seed/0`), `komki up` schreibt ihn vor dem Start. Eine Sicherung
  entfaellt bewusst: der Inhalt einer unveraenderten Vorlage steht
  vollstaendig im Git-Verlauf, und das Seatbelt-Profil des Vermittlers
  erlaubt nur genau diese beiden Dateinamen.

  Pflege: Wer `label_store_seed/0` oder `room/0` aendert, traegt die bisherigen
  Hashes aus `@current` in `@outdated` ein und setzt `@current` neu; ein
  Test haelt `@current` an den tatsaechlichen Vorlagen fest.
  """

  alias KomkiPolicy.JSON

  @mediator_dir "mediator"

  # SHA-256 der kanonischen Vorlagen. @outdated: fruehere Fassungen auf main
  # (#106 und #107 fuer die Registry, beide mit demselben Raum; #134 nur
  # fuer den Raum; 8dc75f9 vor #213 fuer beide).
  @current %{
    "registry.json" => "038a1756f2be26e6a13b844e802d15afbb6b9d65fc5b05a19ffb168066ffcc62",
    "room.json" => "8bb7a156134d43ebd4cc0027fc66ec27c26e00ae696d0d65f83b8ad8c9d57469"
  }
  @outdated %{
    "registry.json" => [
      "fed48d30194094c6e84be239ef40bf74be88457b1aaec09cb3dce8b5bb090e4f",
      "d2b6a4e987036711a517a31dc40368dea82f7136b4213fbf9614cf290ba6d22f",
      # bis #208: Lockerungsbefugnis von doc-pending-freigabe in Engine-Form
      "38e86ed685b8887ddac4eb1976873b105fb1f272ce6c8ff67ac806370c8ecdf7",
      # 8dc75f9: vor #213 (ohne doc-oeffentlich@2)
      "2c7391d3c63e5e06a1910372cb8632026f35f288f750cd3d87b2195db575d835"
    ],
    "room.json" => [
      "127831a737e7f5565d8def234c260ca270056b8954b346725f03ef638ef0b51f",
      # 05b9b2d: Objekte noch ohne Typ (vor #134)
      "4b3ac34dc5ac6a81ea5cb81178cd1fea9f0045e753a079823aab98f6ea45fe32",
      # 8dc75f9: vor #213 (Dokument-Label nicht in B_W)
      "e16da13d5a89a0cf48204c24a3e2ef5c5b13a4fa778949dc6a76fa2e89729298"
    ]
  }

  @observers ["brave-search", "nutzende-person", "pi-agent", "ris-betreiber"]

  # Beobachtertypen (Label-Store, R.2.5): nur eine Person darf
  # klassifizieren; Agent und Empfaenger sind Verarbeitungsdomaenen.
  @observer_types %{
    "brave-search" => "processing_domain",
    "nutzende-person" => "person",
    "pi-agent" => "processing_domain",
    "ris-betreiber" => "processing_domain"
  }

  @doc """
  Vorlage des Arbeitsraums in Store-Form `komki-label-store/2` (Ticket
  #208): die eine Quelle fuer Γ. `komki setup` und `komki up` importieren
  sie in den Label-Store; `<base>/mediator/registry.json` ist dessen
  Export. `registry/0` ist die Projektion dieses Seeds und damit genau das,
  was der Export liefert.
  """
  @spec label_store_seed() :: map()
  def label_store_seed do
    %{
      "schema" => "komki-label-store/2",
      "registry_id" => "reg-komki-arbeitsraum",
      "observers" => @observers,
      "observer_types" => @observer_types,
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
          "mediator-ping@1" =>
            binding("Liveness-Probe des Vermittlers", ["nutzende-person", "pi-agent"], %{
              "admit" => true
            }),
          "doc-oeffentlich@1" =>
            binding("Öffentliches Raumdokument", ["nutzende-person", "pi-agent"], %{
              "admit" => true
            }),
          # Seit #213 steht das Dokument-Label in B_W und gilt damit fuer
          # jede Operation des Raums. Mit Empfaengerkreis und Operationen
          # von @1 sperrte das in recherche RIS und Websuche; Bindungen sind
          # unveraenderlich (R.2.1), darum eine neue Fassung, offen wie die
          # oeffentlichen Connector-Bindungen.
          "doc-oeffentlich@2" =>
            binding("Öffentliches Raumdokument", @observers, %{"admit" => true, "emit" => true}),
          "doc-vertraulich@1" =>
            binding("Vertrauliches Raumdokument", ["nutzende-person", "pi-agent"], %{
              "admit" => %{"eq" => ["purpose", "vertraulich"]}
            }),
          "doc-pending-freigabe@1" =>
            "Raumdokument in Freigabe-Pause"
            |> binding(["nutzende-person", "pi-agent"], %{
              "admit" => %{"eq" => ["vertraulich_freigabe", true]}
            })
            |> Map.put("relaxation_authorities", [
              %{
                "authority" => "nutzende-person",
                "restriction" => "operations",
                "output" => "freigabe-notiz"
              }
            ])
        })
    }
  end

  @doc """
  Registry-Term des Default-Arbeitsraums (`komki-registry/2`): die
  Projektion von `label_store_seed/0` auf die Engine-Form, so wie der
  Label-Store exportiert. Lockerungsbefugnisse exportiert der Store bis
  #109 als `[]` (fail-closed).
  """
  def registry do
    seed = label_store_seed()

    seed
    |> Map.drop(["observer_types"])
    |> Map.put("schema", "komki-registry/2")
    |> Map.put(
      "bindings",
      Map.new(seed["bindings"], fn {id, b} ->
        {id,
         b
         |> Map.take(["readers", "operations"])
         |> Map.put("relaxation_authorities", [])}
      end)
    )
  end

  defp binding(bezeichnung, readers, operations) do
    %{
      "bezeichnung" => bezeichnung,
      "geltungsbereich" => "komki-Arbeitsraum (Vorlage)",
      "verantwortliche_stelle" => "nutzende-person",
      "readers" => readers,
      "operations" => operations,
      "auflagen" => [],
      "relaxation_authorities" => []
    }
  end

  # Connector-Bindungen (Connector-Vertrag §7): admit und emit ohne
  # Bedingung. Die Trennung leistet der Empfaengerkreis: vault-vertraulich
  # liest nur nutzende-person und pi-agent, damit faellt in einem Raum mit
  # dieser Bindung jede Anfrage an RIS oder Websuche an recipient_inclusion.
  defp connector_bindings do
    open = %{"admit" => true, "emit" => true}

    %{
      "ris-oeffentlich@1" => binding("Öffentliche RIS-Inhalte", @observers, open),
      "web-oeffentlich@1" => binding("Öffentliche Web-Treffer", @observers, open),
      "vault-oeffentlich@1" => binding("Öffentliche Vault-Notiz", @observers, open),
      "vault-vertraulich@1" =>
        binding("Vertrauliche Vault-Notiz", ["nutzende-person", "pi-agent"], open)
    }
  end

  @doc "B_W des Referenzraums recherche (Default-Raum)."
  @spec recherche_bindings() :: [String.t()]
  def recherche_bindings,
    do: ["doc-oeffentlich@2", "ris-oeffentlich@1", "vault-oeffentlich@1", "web-oeffentlich@1"]

  @doc "B_W des Referenzraums vertraulich (Connector-Vertrag §7)."
  @spec vertraulich_bindings() :: [String.t()]
  def vertraulich_bindings,
    do: [
      "doc-oeffentlich@2",
      "ris-oeffentlich@1",
      "vault-oeffentlich@1",
      "vault-vertraulich@1",
      "web-oeffentlich@1"
    ]

  @doc """
  Raum-Term des Default-Arbeitsraums. `workspace_bindings` ist B_W des
  Referenzraums recherche. Darin liegt nur `doc-oeffentlich`; die beiden
  anderen Beispieldokumente tragen Labels ausserhalb von B_W und sind hier
  nicht zulaessig (R.5.4, #213), `list_documents` nennt sie nicht. Bewusst
  OHNE die `vertraulich_freigabe`-Fakt: in einem Raum mit
  `doc-pending-freigabe@1` in B_W faehrt die Aufnahme damit die
  indeterminate-Route (missing_fact).
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
        "mediator-ping" => %{
          "type" => "ping",
          "version" => "v1",
          "labels" => ["mediator-ping@1"]
        },
        "doc-oeffentlich" => %{
          "type" => "document",
          "version" => "v1",
          "labels" => ["doc-oeffentlich@2"]
        },
        "doc-vertraulich" => %{
          "type" => "document",
          "version" => "v1",
          "labels" => ["doc-vertraulich@1"]
        },
        "doc-pending-freigabe" => %{
          "type" => "document",
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
  Provisioniert `<base>/mediator/`: legt fehlende Vorlagen je Datei an und
  ersetzt unveraenderte fruehere Fassungen (Ticket #177). Je Datei, weil
  `komki up` die `registry.json` als Export des Label-Store schreibt, bevor
  der Vermittler zum ersten Mal startet (#208); `room.json` und die
  Beispieldokumente fehlen dann noch. Ergebnis: `:ok` (etwas neu angelegt),
  `:already_provisioned`, `{:migrated, from}` (alte Vorlagen ersetzt).
  """
  @spec provision!(Path.t()) :: :ok | :already_provisioned | {:migrated, String.t()}
  def provision!(base_dir) do
    mediator_dir = Path.join(base_dir, @mediator_dir)

    case Enum.reject(["registry.json", "room.json"], &File.exists?(Path.join(mediator_dir, &1))) do
      [] ->
        migrate(mediator_dir)

      missing ->
        write_templates(mediator_dir, missing)
        :ok
    end
  end

  # Je Datei (Ticket #208): registry.json erzeugt komki_cli als Export des
  # Label-Store, eine Paarbindung an room.json gibt es deshalb nicht mehr.
  # Ersetzt wird nur eine unveraenderte alte Vorlage; eigene Dateien bleiben.
  defp migrate(mediator_dir) do
    case Enum.filter(["registry.json", "room.json"], &(state(mediator_dir, &1) == :outdated)) do
      [] ->
        :already_provisioned

      files ->
        write_templates(mediator_dir, files)
        {:migrated, "unveraenderte Vorlagen einer frueheren Fassung: " <> Enum.join(files, ", ")}
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

  # Dokumente nur anlegen, wenn sie fehlen: vorhandene bleiben unberuehrt.
  defp write_templates(mediator_dir, files) do
    documents_dir = Path.join(mediator_dir, room()["documents_dir"])
    File.mkdir_p!(documents_dir)

    for file <- files do
      term = if file == "registry.json", do: registry(), else: room()
      File.write!(Path.join(mediator_dir, file), JSON.canonical(term))
    end

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
