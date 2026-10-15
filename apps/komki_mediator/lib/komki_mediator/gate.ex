defmodule KomkiMediator.Gate do
  @moduledoc """
  Das Gate zwischen pi (MCP-Toolaufruf) und dem Connector-Vollzug.

  * Gate 1 - Policy-Entscheidung VOR dem Vollzug: der exakte Call
    (Tool-Name plus vollstaendig gerenderte Parameter) wird kanonisiert
    und gehasht (`intent_hash`), das Objekt aufgeloest, Intent + Snapshot
    gebaut und `KomkiPolicy.Derive.decide/3` gestellt. Ein `deny` oder
    `indeterminate` tritt niemals als nackter Fehler auf, sondern als
    Remedy-Plan: die Ordnung der behebbaren Schritte IST die Antwort.
  * Gate 2 - Beweispruefung NACH dem Vollzug: das vollzogene Ergebnis wird
    gehasht und unabhaengig durch `KomkiPolicy.Verify.check/4` neu
    geprueft, und das realisierte Payload wird gegen den Gamma-Snapshot
    geprueft: `object_id`, Version und Labels des Ergebnisses muessen zum
    entschiedenen Objekt passen. Faellt eine Pruefung aus, wird der
    Inhalt zurueckgehalten (`"admitted" => "redacted"`); der
    Modellkontext sieht dann nie den unbelegten Payload.
  * Jeder Ablauf haengt EINEN PDR-Auditdatensatz an (synchron via Journal)
    und bettet die `decision_id` in die Antwort ein - zitierfaehig.

  Der `payload_hash` bindet die Bytes, die die MCP-Schicht wirklich
  zurueckgibt (den Modellkontext), nicht den ungefilterten
  Connector-Payload. Anker ist NICHT RFC 0003 R.4.4 (der die
  Payload-Bindung nicht definiert, sondern nur die Vermittler- und
  Journal-Writer-Pflicht), sondern die Options-Recherche Paragraph 5
  ("SHA256(return_bytes)") und Calibration move 2 ("bind each decision
  record to the intent hash, the payload hash, and a Gamma snapshot
  hash").

  Technisch: es wird die Antwort ohne ihr eigenes `payload_hash`-Feld
  gehasht (kein Selbstbezug) - im Admitted-Fall das vollzogene Ergebnis
  samt Entscheidungsmarkierung, im Rueckhalte-Fall die Rueckhalte-Antwort
  selbst.
  """

  alias KomkiMediator.{Fassung, Hash, Journal, Remedy, Room}
  alias KomkiPolicy.{Derive, JSON, Verify}

  @typedoc "Ablauf-Umgebung: Gamma-Stand, Raum, Journal-Anbindung."
  @type env() :: %{
          :gamma => map(),
          :room => Room.t(),
          :journal => GenServer.server(),
          optional(atom()) => term()
        }

  @typedoc "Der Vollzug (Connector-Operation) - laeuft nur nach einem Permit."
  @type executor() :: (-> {:ok, map()} | {:error, term()})

  @response_schema "komki-pdr/1"

  # -------------------------------------------------------------------------
  # Gate 1: Aufruf, Intent/Snapshot, Entscheidung
  # -------------------------------------------------------------------------

  @doc "Vermittelt einen Toolaufruf: Entscheidung, Vollzug, Rueckhaltung, PDR."
  @spec call(env(), String.t(), %{String.t() => term()} | struct(), executor()) :: map()
  def call(env, tool, params, executor) when is_binary(tool) and is_map(params) do
    # Der exakte Call ist die Hash-Basis: nicht eine Projektion der
    # Parameter, sondern das vollstaendig gerenderte Parameter-Map
    # (String-Schluessel). Jedes kuenftige Schema-Feld landet damit
    # mechanisch im intent_hash.
    rendered = rendered_params(params)
    intent_hash = Hash.sha256_hex(JSON.canonical(%{"tool" => tool, "params" => rendered}))

    case Room.object_for_call(env.room, tool, rendered) do
      {:ok, object} ->
        decide(env, tool, intent_hash, object, executor)

      {:error, :unknown_object, object_id} ->
        unknown_object(env, tool, intent_hash, object_id)
    end
  end

  # -------------------------------------------------------------------------
  # Gate 2: Vollzug und unabhaengige Beweispruefung
  # -------------------------------------------------------------------------

  @doc """
  Gate 2: unterwirft das Vollzugsergebnis der unabhaengigen Beweispruefung.
  Beweis klar durchgereicht (`valid`) und Payload passend -> Admit
  (markieren); das Gegenteil -> Rueckhaltung (filtern); Executor-Fehler
  -> `admitted: false`. In allen Faellen: PDR.
  """
  @spec admit_result(
          env(),
          String.t(),
          String.t(),
          map(),
          map(),
          map(),
          {:ok, map()} | {:error, term()}
        ) :: map()
  def admit_result(env, tool, intent_hash, intent, snapshot, decision, executor_outcome) do
    decision_id = new_decision_id()

    case executor_outcome do
      {:ok, result} ->
        admit_checked(env, tool, intent_hash, intent, snapshot, decision, result, decision_id)

      {:error, reason} ->
        admit_failed(env, tool, intent_hash, decision, reason, decision_id)
    end
  end

  # -------------------------------------------------------------------------
  # Entscheidungspfade
  # -------------------------------------------------------------------------

  defp decide(env, tool, intent_hash, object, executor) do
    intent = intent(env.room, intent_hash, object)
    snapshot = Room.snapshot_for(env.room, env.gamma, object, Hash.digest12(intent_hash))

    case Derive.decide(env.gamma.compiled, snapshot, intent) do
      {:ok, %{"decision" => "permit"} = decision} ->
        admit_result(env, tool, intent_hash, intent, snapshot, decision, executor.())

      {:ok, %{"decision" => kind} = decision} when kind in ["deny", "indeterminate"] ->
        not_admitted(env, tool, intent_hash, intent, snapshot, kind, decision)

      {:unsupported, info} ->
        error_path(
          env,
          tool,
          intent_hash,
          intent["intent_id"],
          snapshot["snapshot_id"],
          "unsupported",
          info
        )

      {:error, err} ->
        error_path(
          env,
          tool,
          intent_hash,
          intent["intent_id"],
          snapshot["snapshot_id"],
          "error",
          error_detail(err)
        )
    end
  end

  defp not_admitted(env, tool, intent_hash, intent, snapshot, kind, decision) do
    decision_id = new_decision_id()
    remedies = Remedy.from_decision(decision, env.gamma)

    response = %{
      "decision" => kind,
      "decision_id" => decision_id,
      "registry_id" => env.gamma.registry_id,
      "remedies" => remedies,
      "relaxation_authorities" => Remedy.relaxation_authorities(remedies)
    }

    journal_pdr(
      env,
      pdr(env, tool, kind, "not_admitted", false, intent_hash, %{
        decision_id: decision_id,
        intent_id: intent["intent_id"],
        snapshot_id: snapshot["snapshot_id"],
        checked_label: decision["checked_label"],
        remedies: remedies,
        payload_hash: payload_hash(response)
      })
    )

    response
  end

  defp admit_checked(env, tool, intent_hash, intent, snapshot, decision, result, decision_id) do
    case Verify.check(env.gamma.compiled, snapshot, intent, decision["proof"]) do
      {:ok, %{"result" => "valid"}} ->
        # Beweis klar: das realisierte Payload muss im zweiten Pruefschritt
        # zum entschiedenen Objekt passen (Gamma-Bezug: der Permit deckt
        # die Labels des entschiedenen Objekts - ein vertauschtes
        # Vollzugsergebnis ist nicht gedeckt).
        case check_payload(env.room, snapshot, result) do
          :ok ->
            # Markieren: Ergebnis mit Entscheidungslabels versehen. Der
            # payload_hash gilt der Basis - der gemergten Antwort ohne ihr
            # eigenes payload_hash-Feld (kein Selbstbezug); PDR und
            # Response tragen denselben Hash.
            base =
              Map.merge(result, %{
                "decision" => "permit",
                "decision_id" => decision_id,
                "labels" => decision["checked_label"]
              })

            payload_hash = Hash.sha256_hex(JSON.canonical(base))

            response = Map.put(base, "payload_hash", payload_hash)

            journal_pdr(
              env,
              pdr(env, tool, "permit", "admitted", true, intent_hash, %{
                decision_id: decision_id,
                intent_id: intent["intent_id"],
                snapshot_id: snapshot["snapshot_id"],
                checked_label: decision["checked_label"],
                remedies: nil,
                payload_hash: payload_hash
              })
            )

            response

          {:payload_mismatch, codes} ->
            redact(
              env,
              tool,
              intent_hash,
              decision_id,
              "realisiertes Payload passt nicht zum entschiedenen Objekt",
              codes
            )
        end

      {:ok, %{"result" => "invalid", "reasons" => reasons}} ->
        redact(
          env,
          tool,
          intent_hash,
          decision_id,
          "unabhaengige Beweispruefung fehlgeschlagen",
          reasons
        )

      {:error, err} ->
        redact(
          env,
          tool,
          intent_hash,
          decision_id,
          "unabhaengige Beweispruefung fehlgeschlagen",
          [error_detail(err)]
        )
    end
  end

  defp redact(env, tool, intent_hash, decision_id, reason, verify_output) do
    # Rueckhaltung: kein Ergebnisinhalt tritt raus, keine Remedies
    # (Integritaetsfehler - es gibt keine nachreichbare Gamma-Evidenz).
    # Der payload_hash bindet die Rueckhalte-Antwort jenseits seines
    # eigenen Feldes - genau die Bytes, die der Modellkontext zu sehen
    # bekommt.
    core = %{
      "decision" => "permit",
      "admitted" => "redacted",
      "decision_id" => decision_id,
      "reason" => reason,
      "verify" => verify_output
    }

    payload_hash = payload_hash(core)

    journal_pdr(
      env,
      pdr(env, tool, "permit", "redacted", "redacted", intent_hash, %{
        decision_id: decision_id,
        payload_hash: payload_hash,
        remedies: nil
      })
    )

    Map.put(core, "payload_hash", payload_hash)
  end

  defp admit_failed(env, tool, intent_hash, decision, reason, decision_id) do
    response = %{
      "decision" => "permit",
      "admitted" => false,
      "decision_id" => decision_id,
      "error" => render(reason)
    }

    journal_pdr(
      env,
      pdr(env, tool, "permit", "error", false, intent_hash, %{
        decision_id: decision_id,
        checked_label: decision["checked_label"],
        remedies: nil,
        payload_hash: payload_hash(response)
      })
    )

    response
  end

  defp unknown_object(env, tool, intent_hash, object_id) do
    decision_id = new_decision_id()

    response = %{
      "decision" => "error",
      "decision_id" => decision_id,
      "detail" => "unbekanntes Objekt: " <> Kernel.inspect(object_id)
    }

    journal_pdr(
      env,
      pdr(env, tool, "error", "not_admitted", false, intent_hash, %{
        decision_id: decision_id,
        remedies: nil,
        payload_hash: payload_hash(response)
      })
    )

    response
  end

  defp error_path(env, tool, intent_hash, intent_id, snapshot_id, pdr_decision, detail) do
    decision_id = new_decision_id()

    response = %{
      "decision" => "error",
      "decision_id" => decision_id,
      "registry_id" => env.gamma.registry_id,
      "detail" => detail
    }

    journal_pdr(
      env,
      pdr(env, tool, pdr_decision, "error", false, intent_hash, %{
        decision_id: decision_id,
        intent_id: intent_id,
        snapshot_id: snapshot_id,
        remedies: nil,
        payload_hash: payload_hash(response)
      })
    )

    response
  end

  # -------------------------------------------------------------------------
  # Bausteine
  # -------------------------------------------------------------------------

  # Gate 2, zweiter Pruefschritt (Payload-Bindung): das realisierte
  # Vollzugsergebnis muss dem Objekt entsprechen, das im entschiedenen
  # Snapshot verzeichnet ist. Der Permit deckt die Labels des entschiedenen
  # Objekts - ein vertauschtes Vollzugsergebnis ist nicht gedeckt. Ein
  # fehlender Objekt-Claim ist nicht pruefbar und faellt fail-closed unter
  # die Rueckhaltung.
  @spec check_payload(Room.t(), map(), map()) :: :ok | {:payload_mismatch, [String.t()]}
  defp check_payload(room, snapshot, result) do
    case Map.get(result, "object_id") do
      object_id when is_binary(object_id) -> claim_check(room, snapshot, object_id)
      _other -> {:payload_mismatch, ["payload_identity_missing"]}
    end
  end

  defp claim_check(room, snapshot, object_id) do
    case Room.object_for_claim(room, object_id) do
      {:ok, object} ->
        decided = snapshot["object"]

        if object.object_id == decided["object_id"] and
             object.version == decided["version"] and
             object.labels == decided["labels"] do
          :ok
        else
          {:payload_mismatch, ["payload_object_mismatch"]}
        end

      {:error, :unknown_object, _object_id} ->
        {:payload_mismatch, ["payload_object_unknown"]}
    end
  end

  # Exakte Parameter-Fassung des Calls: der vollstaendig gerenderte Call
  # ist die Hash-Basis fuer den intent_hash - nicht eine Projektion.
  # Structs (die vom MCP-Schema gerenderten Parameter) werden entpackt,
  # Atom-Schluessel werden String-Schluessel (der Vertrag zwischen
  # MCP-Schicht und Gate), String-Schluessel bleiben unveraendert.
  @spec rendered_params(term()) :: %{String.t() => term()}
  defp rendered_params(params) when is_struct(params),
    do: rendered_params(Map.from_struct(params))

  defp rendered_params(params) when is_map(params) do
    Map.new(params, fn {key, value} -> {render_key(key), value} end)
  end

  defp render_key(key) when is_atom(key), do: Atom.to_string(key)
  defp render_key(key) when is_binary(key), do: key

  defp intent(room, intent_hash, object) do
    %{
      "schema" => "komki-intent/1",
      "intent_id" => "intent-" <> Hash.digest12(intent_hash),
      "operation" => "admit",
      "object" => object.object_id <> "@" <> object.version,
      "workspace" => room.workspace_id
    }
  end

  defp pdr(env, tool, decision, outcome, admitted, intent_hash, opts) do
    %{
      "schema" => @response_schema,
      "decision_id" => opts.decision_id,
      "tool" => tool,
      "decision" => decision,
      "outcome" => outcome,
      "admitted" => admitted,
      "intent_hash" => intent_hash,
      "payload_hash" => opts.payload_hash,
      "gamma" => %{"registry_id" => env.gamma.registry_id, "gamma_hash" => env.gamma.gamma_hash},
      "intent_id" => Map.get(opts, :intent_id),
      "snapshot_id" => Map.get(opts, :snapshot_id),
      "checked_label" => Map.get(opts, :checked_label),
      "remedies" => Map.get(opts, :remedies),
      "abrufdatum" => DateTime.to_iso8601(DateTime.utc_now()),
      "fassung_id" => Fassung.fassung_id()
    }
  end

  defp payload_hash(term), do: Hash.sha256_hex(JSON.canonical(term))

  defp journal_pdr(env, record), do: Journal.append(env.journal, record)

  defp new_decision_id do
    "pdr-" <> Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)
  end

  # Eingabefehler-Map (atom-Key-Form, wie JSON.parse sie liefert) in die
  # JSON-wuerdige String-Schluesselform ueberfuehren.
  defp error_detail(err) do
    %{
      "code" => Atom.to_string(Map.fetch!(err, :code)),
      "path" => Map.fetch!(err, :path),
      "detail" => Map.fetch!(err, :detail)
    }
  end

  # Der Vollzugsfehler geht als JSON-wuerdige Fassung raus (POSIX-Tupel
  # sind nicht kodierbar).
  defp render(reason) when is_binary(reason), do: reason
  defp render(reason), do: Kernel.inspect(reason)
end
