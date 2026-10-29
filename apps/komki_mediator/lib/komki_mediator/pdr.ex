defmodule KomkiMediator.PDR do
  @moduledoc """
  PDR-Auditdatensaetze (Schema `"komki-pdr/3"`): eine gemeinsame Form fuer
  `KomkiMediator.Gate` (ping, admit_document) und
  `KomkiMediator.ConnectorGate` (Connector-Tools).

  Jeder Datensatz traegt dieselben Schluessel; nicht belegte Felder sind
  `null`. Neu gegenueber `komki-pdr/2`:

    * `rule` — der entschiedene Regelzweig (`"admit"` oder `"emit"`).
    * `call_id` — bei Connector-Aufrufen die `decision_id` des emit-PDR;
      emit- und admit-PDR eines Aufrufs tragen dieselbe `call_id`
      (Connector-Vertrag §6).
    * `session_id` — Zuordnung zur pi-Sitzung (aus der Umgebung, darf
      `null` sein; der Socket-Zugang fuellt sie, Connector-Vertrag §8).
    * `assigned_label` — bei emit-Permits die zugeordnete Ausgabe-Menge
      λ(y) = B_W.

  Neben den Entscheidungen schreibt der Vermittler bei jedem Start einen
  Datensatz mit `tool: "workspace"`, `decision: "loaded"`: `checked_label` ist
  das B_W, mit dem er ab jetzt entscheidet, `payload_hash` der SHA-256 von
  `room.json`. Ein Raumwechsel (Ticket #268) zeigt sich als zwei solche
  Datensaetze mit verschiedenem B_W.

  `seq` und `prev_hash` setzt allein der Journal-Writer (Ticket #139).
  """

  alias KomkiMediator.{Fassung, Hash, Journal}
  alias KomkiPolicy.JSON

  @schema "komki-pdr/3"

  @doc "Schema-Kennung der Datensaetze."
  @spec schema() :: String.t()
  def schema, do: @schema

  @doc "Neue, zufaellige Entscheidungskennung `pdr-<32 hex>`."
  @spec new_id() :: String.t()
  def new_id, do: "pdr-" <> Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)

  @doc "SHA-256 ueber die kanonischen Bytes eines JSON-Terms."
  @spec payload_hash(term()) :: String.t()
  def payload_hash(term), do: Hash.sha256_hex(JSON.canonical(term))

  @doc """
  Baut einen Datensatz. `fields` (String-Schluessel) ueberschreibt die
  Vorbelegung; `decision_id` ist Pflicht.
  """
  @spec record(map(), %{String.t() => term()}) :: map()
  def record(env, %{"decision_id" => _} = fields) do
    defaults = %{
      "schema" => @schema,
      "tool" => nil,
      "rule" => nil,
      "call_id" => nil,
      "session_id" => Map.get(env, :session_id),
      "decision" => nil,
      "outcome" => nil,
      "admitted" => nil,
      "intent_hash" => nil,
      "payload_hash" => nil,
      "gamma" => %{"registry_id" => env.gamma.registry_id, "gamma_hash" => env.gamma.gamma_hash},
      "intent_id" => nil,
      "snapshot_id" => nil,
      "checked_label" => nil,
      "assigned_label" => nil,
      "remedies" => nil,
      "abrufdatum" => DateTime.to_iso8601(DateTime.utc_now()),
      "fassung_id" => Fassung.fassung_id()
    }

    Map.merge(defaults, fields)
  end

  @doc "Baut den Datensatz und haengt ihn synchron an das Journal an."
  @spec append(map(), %{String.t() => term()}) :: :ok
  def append(env, fields), do: Journal.append(env.journal, record(env, fields))
end
