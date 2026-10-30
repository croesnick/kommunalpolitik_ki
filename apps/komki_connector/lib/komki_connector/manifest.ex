defmodule KomkiConnector.Manifest do
  @moduledoc """
  Die Connector-Manifeste (CONTRACT.md §5): einzige Quelle fuer Fassung,
  Operationen samt Parameter-Schema, Egress-Hosts, Dateisystem-Pfade,
  Credentials (Keychain-Service), emit-Umgebung und Import-Labels.

  Vermittler (MCP-Tools, Gate), `komki_cli` (Profilgenerator, Start,
  Doctor) und die Connectoren lesen dieses Modul — kein zweiter Ort.

  Die Manifeste sind Funktionen statt Modulattribute, weil kompilierte
  Regexe unter OTP 28 nicht in Attributen gespeichert werden duerfen.
  """

  @type op_spec :: %{
          tool: String.t(),
          kind: :read | :write,
          params: Sidecar.Params.schema(),
          description: String.t()
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

  @ids ["documents", "ris", "vault", "web"]

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
            "Ein Raumdokument anhand seiner document_id zum Agentenkontext zulassen (z. B. \"doc-oeffentlich\").",
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
