defmodule KomkiPolicy.Stand do
  @moduledoc """
  Offenlegungsstand `komki-stand/1` und der atomare Übergang `advance/2`
  (CONTRACT.md § 2.7, R.6.3).

  Der Stand ist ein versionierter Mini-Ledger: `version` monoton, `as_of`
  logische Ist-Zeit (Eingabe, nie Engine-Zustand, § 1), `consumed` mappt
  verbrauchte Noncen auf die verbrauchende release-id. `advance/2` ist
  rein und atomar (Compare-and-Swap über die Version): Erfolg nur, wenn
  `stand_ref` exakt `<stand_id>@<version>` des übergebenen Standes
  adressiert, `stand_version_after` genau `version + 1` beträgt und die
  Nonce noch nicht verbraucht ist. Zwei konkurrierende
  Ausführungen desselben GOs können nicht beide committet werden — das
  Führen des aktuellen Standes ist Vollzug außerhalb des Kerns (B.8).
  """

  alias KomkiPolicy.{Registry, Validations}

  @fields ["schema", "stand_id", "version", "scope", "as_of", "consumed"]

  @type t() :: %{
          required(:stand_id) => String.t(),
          required(:version) => non_neg_integer(),
          required(:scope) => String.t(),
          required(:as_of) => integer(),
          required(:consumed) => %{String.t() => String.t()}
        }

  @type refusal() :: %{
          required(:code) => :stand_version_conflict | :nonce_already_consumed,
          required(:detail) => String.t()
        }

  @type error() :: %{
          required(:code) => atom(),
          required(:path) => String.t(),
          required(:detail) => String.t()
        }

  @doc "Rekonstruiert den JSON-Datensatz eines validierten/fortgeschriebenen Standes (kanonisch encodierbar)."
  @spec to_record(t()) :: json_record()
  def to_record(stand) do
    %{
      "schema" => "komki-stand/1",
      "stand_id" => stand.stand_id,
      "version" => stand.version,
      "scope" => stand.scope,
      "as_of" => stand.as_of,
      "consumed" => stand.consumed
    }
  end

  @doc "Validiert einen geparsten Stand-Term (§ 2.7)."
  @spec validate(term()) :: {:ok, t()} | {:error, error()}
  def validate(term) do
    case validate_reason(term) do
      {:ok, stand} -> {:ok, stand}
      {:error, {code, path, detail}} -> {:error, %{code: code, path: path, detail: detail}}
    end
  end

  @typedoc "JSON-Datensatz (String-Schlüssel) gemäß § 2.7."
  @type json_record() :: %{required(String.t()) => term()}

  @doc """
  Atomarer Standübergang (§ 2.7): `vorschlag` ist das `release`-Objekt
  einer Permit-Entscheidung des Freigabe-Zweigs (Form § 4.6: `release_id`,
  `nonce`, `stand_ref`, `stand_version_after`, `call_hash`). Ein Vorschlag
  außerhalb der § 4.6-Form ist ein Eingabefehler (`{:error, …}`); Erfolg
  liefert den nächsten Stand (`version + 1`, `consumed` erweitert); sonst
  `{:refused, %{code: …}}`.
  """
  @spec advance(%{String.t() => term()}, term()) ::
          {:ok, t()} | {:refused, refusal()} | {:error, error()}
  def advance(stand, vorschlag) do
    with {:ok, current} <- validate(stand),
         {:ok, proposal} <- validate_proposal(vorschlag) do
      do_advance(current, proposal)
    else
      # validate/1 liefert die strukturierte Fehler-Map direkt — sonst krachte
      # ein schema-ungültiger Stand in WithClauseError (CLI-Exit 4 statt 2);
      # validate_proposal/1 liefert das Reason-Tupel.
      {:error, %{} = error} ->
        {:error, error}

      {:error, {code, path, detail}} ->
        {:error, %{code: code, path: path, detail: detail}}
    end
  end

  # CAS (§ 2.7): der Vorschlag muss exakt den NÄCHSTEN Stand adressieren —
  # `stand_ref` auf den aktuellen Stand und `stand_version_after == version + 1`
  # (#120). Ein handgemachter Vorschlag mit abweichender Zielversion ist ein
  # Versionskonflikt, kein Commit.
  defp do_advance(current, proposal) do
    if addresses_next_version?(current, proposal) do
      claim_nonce(current, proposal)
    else
      {:refused,
       %{
         :code => :stand_version_conflict,
         :detail =>
           "proposal stand_ref " <>
             Kernel.inspect(proposal.stand_ref) <>
             " with stand_version_after " <>
             Integer.to_string(proposal.stand_version_after) <>
             " does not address current version " <>
             Integer.to_string(current.version)
       }}
    end
  end

  defp addresses_next_version?(current, proposal) do
    proposal.stand_ref == current.stand_id <> "@" <> Integer.to_string(current.version) and
      proposal.stand_version_after == current.version + 1
  end

  defp claim_nonce(current, proposal) do
    if Map.has_key?(current.consumed, proposal.nonce) do
      {:refused,
       %{
         :code => :nonce_already_consumed,
         :detail => "nonce " <> Kernel.inspect(proposal.nonce) <> " is already consumed"
       }}
    else
      {:ok,
       Map.merge(current, %{
         version: current.version + 1,
         consumed: Map.put(current.consumed, proposal.nonce, proposal.release_id)
       })}
    end
  end

  # -------------------------------------------------------------------------
  # Validierung: Stand (§ 2.7)
  # -------------------------------------------------------------------------

  defp validate_reason(term) do
    with {:ok, _} <- Validations.require_map(term, "$"),
         :ok <- Validations.require_schema(term, "komki-stand/1", :missing_field),
         :ok <- Validations.closed_fields(term, @fields, "$"),
         :ok <- Validations.require_kebab(term["stand_id"], "$.stand_id"),
         :ok <-
           Validations.require_nonneg_integer(
             term["version"],
             "$.version",
             :invalid_stand_version
           ),
         :ok <- Validations.require_kebab(term["scope"], "$.scope"),
         :ok <- Validations.require_integer(term["as_of"], "$.as_of", :invalid_as_of),
         :ok <- validate_consumed(term["consumed"], "$.consumed") do
      {:ok,
       %{
         stand_id: term["stand_id"],
         version: term["version"],
         scope: term["scope"],
         as_of: term["as_of"],
         consumed: term["consumed"]
       }}
    end
  end

  defp validate_consumed(map, _path) when map_size(map) == 0, do: :ok

  defp validate_consumed(map, path) when is_map(map) do
    entries = Map.to_list(map)
    bad_nonce = Enum.find(entries, fn {nonce, _} -> not Registry.kebab_id?(nonce) end)
    bad_release = Enum.find(entries, fn {_, release_id} -> not Registry.kebab_id?(release_id) end)

    case {bad_nonce, bad_release} do
      {nil, nil} ->
        :ok

      {{nonce, _}, _} ->
        {:error,
         {:invalid_reference_id, path, "not a kebab-case nonce: " <> Kernel.inspect(nonce)}}

      {_, {_, release_id}} ->
        {:error,
         {:invalid_reference_id, path,
          "not a kebab-case release_id: " <> Kernel.inspect(release_id)}}
    end
  end

  defp validate_consumed(other, path) do
    {:error, {:invalid_record, path, "expected an object, got " <> Kernel.inspect(other)}}
  end

  # -------------------------------------------------------------------------
  # Validierung: Verbrauchs-Vorschlag (Form § 4.6, geschlossene Feldmenge)
  # -------------------------------------------------------------------------

  @proposal_fields ["release_id", "nonce", "stand_ref", "stand_version_after", "call_hash"]

  defp validate_proposal(term) when is_map(term) do
    with :ok <- closed_proposal_fields(term) do
      case Enum.reject(@proposal_fields, &Map.has_key?(term, &1)) do
        [] ->
          proposal_shape(term)

        missing ->
          {:error,
           {:invalid_proposal, "$", "missing proposal fields: " <> Enum.join(missing, ", ")}}
      end
    end
  end

  defp validate_proposal(term) do
    {:error, {:invalid_proposal, "$", "expected an object, got " <> Kernel.inspect(term)}}
  end

  # Geschlossene Feldmenge nach der § 4.6-Form; Extra-Felder sind Eingabefehler
  # (`unknown_field`) — dieselbe Strenge wie bei allen Schemata des Vertrags.
  defp closed_proposal_fields(term) do
    case Enum.sort(Enum.reject(Map.keys(term), &(&1 in @proposal_fields))) do
      [] ->
        :ok

      [first | _] ->
        {:error, {:unknown_field, "$." <> first, "field not part of the closed proposal schema"}}
    end
  end

  # Intake nach der geschlossenen § 4.6-Form (#120): `release_id` und `nonce`
  # landen im fortgeschriebenen `consumed`-Ledger (Kebab, sonst verletzt
  # `to_record/1` des Ergebnisses die Ausgabe-Invariante), `stand_ref` trägt
  # die `<stand_id>@<version>`-Form (`Registry.reference_id?/1`), `call_hash`
  # ist SHA-256-Hex und `stand_version_after` eine nicht-negative Ganzzahl.
  # Die Bindung von `stand_ref`/`stand_version_after` an den aktuellen Stand
  # prüft `do_advance/2` — hier geht es nur um die Form der Eingabe.
  defp proposal_shape(term) do
    with :ok <- Validations.require_kebab(term["release_id"], "$.release_id"),
         :ok <- Validations.require_kebab(term["nonce"], "$.nonce"),
         :ok <- require_stand_ref(term["stand_ref"]),
         :ok <- Validations.require_hex64(term["call_hash"], "$.call_hash", :invalid_proposal),
         :ok <-
           Validations.require_nonneg_integer(
             term["stand_version_after"],
             "$.stand_version_after",
             :invalid_proposal
           ) do
      {:ok,
       %{
         release_id: term["release_id"],
         nonce: term["nonce"],
         stand_ref: term["stand_ref"],
         stand_version_after: term["stand_version_after"],
         call_hash: term["call_hash"]
       }}
    end
  end

  defp require_stand_ref(value) do
    if Registry.reference_id?(value) do
      :ok
    else
      {:error,
       {:invalid_reference_id, "$.stand_ref",
        "expected <stand_id>@<version>, got " <> Kernel.inspect(value)}}
    end
  end

  # -------------------------------------------------------------------------
end
