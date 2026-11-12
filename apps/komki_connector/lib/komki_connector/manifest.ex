defmodule KomkiConnector.Manifest do
  @moduledoc """
  Die Connector-Manifeste (CONTRACT.md §5): einzige Quelle fuer Fassung,
  Operationen samt Parameter-Schema, Egress-Hosts, Dateisystem-Pfade,
  Credentials (Keychain-Service), emit-Umgebung und Import-Labels.

  Vermittler (MCP-Tools, Gate), `komki_cli` (Profilgenerator, Start,
  Doctor) und die Connectoren lesen dieses Modul — kein zweiter Ort.

  Die Manifeste sind Funktionen statt Modulattribute, weil kompilierte
  Regexe unter OTP 28 nicht in Attributen gespeichert werden duerfen.

  Eine Operation kann eine eigene Umgebung tragen (`environment`, #419);
  sonst gilt die des Connectors (`environment/2`). Eine Operation der Art
  `:admit_only` liest genau ein festes Objekt (`object`), dessen Labels
  die `import_labels` des Manifests sind; der Vermittler entscheidet sie
  nur ueber `admit` (Connector-Vertrag §6.4).
  """

  @type op_spec :: %{
          required(:tool) => String.t(),
          required(:kind) => :read | :write | :admit_only,
          required(:params) => Sidecar.Params.schema(),
          required(:description) => String.t(),
          optional(:environment) => String.t(),
          optional(:object) => String.t(),
          optional(:ausgabeart) => String.t()
        }

  @type t :: %{
          id: String.t(),
          fassung: String.t(),
          binary: String.t(),
          ops: %{String.t() => op_spec()},
          egress_hosts: [String.t()],
          fs: [{String.t(), :read | :write}],
          credentials: %{String.t() => String.t()},
          environment: String.t(),
          import_labels: [String.t()]
        }

  @ids ["documents", "ratsprojekte", "ris", "vault", "web"]

  @doc "Alle Connector-IDs, sortiert."
  @spec ids() :: [String.t()]
  def ids, do: @ids

  @doc "Alle Manifeste, sortiert nach ID."
  @spec all() :: [t()]
  def all, do: Enum.map(@ids, &fetch!/1)

  @doc """
  Das Manifest als `Sidecar.Server.manifest()`: unveraendert, plus
  `version` = Fassung. Die Library spricht englisch (`version`, auch im
  `ping`), komki bleibt bei der Fassung; uebersetzt wird nur hier.
  """
  @spec sidecar!(String.t()) :: Sidecar.Server.manifest()
  def sidecar!(id) do
    manifest = fetch!(id)
    Map.put(manifest, :version, manifest.fassung)
  end

  @doc "Manifest zu einer ID; unbekannte ID ist ein Programmierfehler."
  @spec fetch!(String.t()) :: t()
  # Raumdokumente (Ticket #169): nur der Vollzug von admit_document. Die
  # Entscheidung faellt vorher im Vermittler (KomkiMediator.Gate) ueber die
  # Objekt-Labels aus room.json; Labels und Umgebung dieses Manifests
  # spielen dafuer keine Rolle (import_labels leer).
  def fetch!("documents") do
    %{
      id: "documents",
      fassung: "komki-documents/1",
      binary: "komki-connector-documents",
      ops: %{
        "read" => %{
          tool: "admit_document",
          kind: :read,
          description:
            "Ein Raumdokument anhand seiner document_id zum Agentenkontext zulassen (z. B. \"doc-oeffentlich\"). " <>
              "PDFs kommen als Text je Seite mit Seitenanker [Seite N], dazu die Highlights der nutzenden Person mit Kommentar und markiertem Text.",
          params: %{
            "document_id" => %{type: :string, max: 64, required: true, pattern: ~r/^[a-z0-9-]+$/}
          }
        }
      },
      egress_hosts: [],
      fs: [{"{documents_dir}", :read}],
      credentials: %{},
      environment: "lokaler-arbeitsraum@1",
      import_labels: []
    }
  end

  def fetch!("ris") do
    %{
      id: "ris",
      fassung: "komki-ris/2",
      binary: "komki-connector-ris",
      ops: %{
        "search" => %{
          tool: "ris_search",
          kind: :read,
          description:
            "Volltextsuche in oeffentlichen Tagesordnungspunkten des Ratsinformationssystems (RIS). " <>
              "Zitiere einen Treffer mit Sitzung, Datum und TOP-Nummer (Feld nummer); " <>
              "top_id ist nur die Kennung fuer ris_show.",
          params: %{
            "text" => %{type: :string, max: 200, required: true},
            "limit" => %{type: :integer, min: 1, max: 20, required: false, default: 10}
          }
        },
        "show" => %{
          tool: "ris_show",
          kind: :read,
          description:
            "Einen oeffentlichen Tagesordnungspunkt des RIS anhand seiner top_id lesen.",
          params: %{
            "top_id" => %{type: :string, max: 64, required: true, pattern: ~r/^[A-Za-z0-9_-]+$/}
          }
        }
      },
      egress_hosts: ["risapi1.komuna.net:443"],
      fs: [],
      credentials: %{},
      environment: "ris-abruf@1",
      import_labels: ["ris-oeffentlich@1"]
    }
  end

  # Weg "Fakt vorschlagen" (Durchstich #409, Bau-Ticket #277): Der
  # ratsprojekte-Connector traegt Szene 11 — EIN Ereignis mit Teilen,
  # ein GO in komki, die Entscheidung im Hub. Schreibend, Umgebung ist
  # der Bestand des Hubs (`ratsprojekte-bestand@1`, Γ-GO vom 2026-11-10).
  # Die Ausgabeart `ratsprojekte-essenz` (Arbeitstitel, Szene 13, #423)
  # benennt das Ziel der Lockerungsbefugnisse: Der Vermittler traegt sie
  # in die GO-Anfrage, die Engine rechnet sie gegen die Zielumgebung nach
  # (§ 4.9). Der Hub-Socket-Pfad kommt aus der config
  # (`ratsprojekte_socket`), das Hub-Token aus dem Schluesselbund-Service
  # unten (der Hub kennt nur den Hash, #415).
  #
  # Weg "Stand lesen" (#419, Szene 12): Der Connector liest die Stand-Datei
  # (`{ratsprojekte_stand}` aus der config), der Hub sieht keine Anfrage.
  # Die Anfrage ist eine Konstante, ihre Umgebung hat nur nutzende Person
  # und Agent als Beobachter: Der Vermittler entscheidet nur die Aufnahme
  # gegen B_W, ohne emit und transfer (Connector-Vertrag §6.4). Das Label
  # `ratsprojekte@1` steht hier und nirgends sonst.
  def fetch!("ratsprojekte") do
    %{
      id: "ratsprojekte",
      fassung: "komki-ratsprojekte/2",
      binary: "komki-connector-ratsprojekte",
      ops: %{
        "stand_lesen" => %{
          tool: "rp_stand_lesen",
          kind: :admit_only,
          object: "ratsprojekte-stand",
          environment: "lokaler-arbeitsraum@1",
          description:
            "Den zuletzt ausgegebenen Stand des ratsprojekte-Hubs lesen: Projekte und Fakten, wie die Redaktion " <>
              "sie freigegeben hat. Nur in einem Raum, der dafuer angelegt ist (Projektraum); der Hub erfaehrt " <>
              "vom Lesen nichts.",
          params: %{}
        },
        "fakt_vorschlagen" => %{
          tool: "rp_fakt_vorschlagen",
          kind: :write,
          ausgabeart: "ratsprojekte-essenz",
          description:
            "Dem ratsprojekte-Hub einen Vorschlag machen: EIN Ereignis mit Teilen, ein GO deckt alle Teile, " <>
              "die Redaktion waehlt im Hub ab, was zum Stand gehoert. Jeder Teil braucht eine Aussage und " <>
              "einen Verweis auf eine Antwort aus diesem Raum; der Vorschlag erscheint dort als nicht verifiziert. " <>
              "Die Projektangabe ist nur ein Hinweis. Aus oeffentlicher Recherche entscheidet die nutzende Person " <>
              "per GO fuer genau diesen Aufruf; aus einem vertraulichen Raum (etwa dem Fraktionsraum) wird der Text " <>
              "dem Vorstand offengelegt — dann entscheidet ein eigenes Freigabefenster, und ein Teil, den sie abwaehlt, " <>
              "verlaesst den Raum nicht.",
          params: %{
            "titel" => %{type: :string, max: 120, required: true},
            "teile" => %{
              type: :list,
              min_items: 1,
              max_items: 8,
              items: %{
                "aussage" => %{type: :string, max: 1000, required: true},
                "quelle" => %{type: :string, max: 400, required: true},
                "fundstelle" => %{type: :string, max: 200, required: false}
              }
            },
            "projekt_hinweis" => %{type: :string, max: 120, required: false}
          }
        }
      },
      egress_hosts: [],
      fs: [{"{ratsprojekte_stand}", :read}],
      credentials: %{"KOMKI_HUB_TOKEN" => "ratsprojekte-hub-token"},
      environment: "ratsprojekte-bestand@1",
      # Label der Stand-Datei (stand_lesen). Der Schreibweg nimmt seine
      # Labels aus assigned_label, nicht von hier.
      import_labels: ["ratsprojekte@1"]
    }
  end

  def fetch!("web") do
    %{
      id: "web",
      fassung: "komki-web/1",
      binary: "komki-connector-web",
      ops: %{
        "search" => %{
          tool: "web_search",
          kind: :read,
          description:
            "Websuche (Brave Search). Der Suchtext verlaesst den Rechner und wird beim Suchanbieter sichtbar.",
          params: %{
            "query" => %{type: :string, max: 400, required: true},
            "count" => %{type: :integer, min: 1, max: 10, required: false, default: 5}
          }
        }
      },
      egress_hosts: ["api.search.brave.com:443"],
      fs: [],
      credentials: %{"BRAVE_API_KEY" => "brave-search-api"},
      environment: "web-suche@1",
      import_labels: ["web-oeffentlich@1"]
    }
  end

  def fetch!("vault") do
    %{
      id: "vault",
      fassung: "komki-vault/1",
      binary: "komki-connector-vault",
      ops: %{
        "search" => %{
          tool: "vault_search",
          kind: :read,
          description:
            "Notizen im Vault nach Text durchsuchen (nur Notizen mit gueltigem Label).",
          params: %{"text" => %{type: :string, max: 200, required: true}}
        },
        "read" => %{
          tool: "vault_read",
          kind: :read,
          description: "Eine Vault-Notiz anhand ihrer note_id (relativer Pfad, .md) lesen.",
          params: %{
            "note_id" => %{
              type: :string,
              max: 200,
              required: true,
              pattern: ~r/^[A-Za-z0-9äöüÄÖÜß _.\/-]+\.md$/u
            }
          }
        },
        "write_test" => %{
          tool: "vault_write_test",
          kind: :write,
          description: "Eine neue Notiz im Testordner des Vaults anlegen (kein Ueberschreiben).",
          params: %{
            "title" => %{type: :string, max: 120, required: true},
            "body" => %{type: :string, max: 20_000, required: true}
          }
        }
      },
      egress_hosts: [],
      fs: [{"{vault_dir}", :read}, {"{vault_dir}/komki-test", :write}],
      credentials: %{},
      environment: "vault-lokal@1",
      # Leer: Vault-Notizen tragen ihre Labels selbst, und es gilt jede
      # Bindung aus Γ (Gate 2 im Vermittler, Ticket #211). Eine von komki
      # geschriebene Notiz traegt lambda(y) = B_W (CONTRACT §6.3).
      import_labels: []
    }
  end

  @doc "Manifest zum MCP-Tool-Namen (z. B. `\"ris_search\"`) samt Operation."
  @spec by_tool(String.t()) :: {:ok, t(), String.t()} | :error
  def by_tool(tool) do
    Enum.find_value(all(), :error, fn manifest ->
      Enum.find_value(manifest.ops, fn
        {op, %{tool: ^tool}} -> {:ok, manifest, op}
        _ -> nil
      end)
    end)
  end

  @doc "Umgebung einer Operation: ihre eigene, sonst die des Connectors."
  @spec environment(t(), String.t()) :: String.t()
  def environment(manifest, op),
    do: Map.get(Map.fetch!(manifest.ops, op), :environment, manifest.environment)

  @doc "Alle MCP-Tool-Namen aller Connectoren, sortiert."
  @spec tools() :: [String.t()]
  def tools do
    Enum.sort(for manifest <- all(), {_op, spec} <- manifest.ops, do: spec.tool)
  end

  @doc "Socket-Pfad eines Connectors unter der komki-Basis (CONTRACT.md §2)."
  @spec socket_path(Path.t(), String.t()) :: Path.t()
  def socket_path(base, id) when id in @ids,
    do: Path.join([base, "run", "connectors", id <> ".sock"])
end
