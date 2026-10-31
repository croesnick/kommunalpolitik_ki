defmodule KomkiMediator.PDR do
  @moduledoc """
  PDR audit records (schema `"komki-pdr/3"`): one shared shape for
  `KomkiMediator.Gate` (ping, admit_document) and
  `KomkiMediator.ConnectorGate` (connector tools).

  Every record carries the same keys; unused fields are `null`. New
  compared to `komki-pdr/2`:

    * `rule` — the decided rule branch (`"admit"`, `"emit"`, `"transfer"`
      or `"store"`).
    * `call_id` — for connector calls, the id of the call; it equals the
      `decision_id` of the emit PDR. Every PDR of the call carries it,
      denials and GO records included (connector contract §6); only a
      rejection in the pre-check has none.
    * `session_id` — the pi session (from the environment, may be `null`;
      the socket access fills it, connector contract §8).
    * `assigned_label` — for emit permits, the assigned output set
      λ(y) = B_W.

  Besides the decisions, the mediator writes a record with
  `tool: "workspace"`, `decision: "loaded"` on every start: `checked_label`
  is the B_W it decides with from now on, `payload_hash` the SHA-256 of
  `room.json`. A room switch (ticket #268) shows up as two such records
  with different B_W.

  Only the journal writer sets `seq` and `prev_hash` (ticket #139).
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
