defmodule KomkiMediator.Gate do
  @moduledoc """
  Das Tor zwischen pi (MCP-Toolaufruf) und dem Connector-Vollzug.

  * Tor 1 - Policy-Entscheidung VOR dem Vollzug: der gerenderte Aufruf
    wird kanonisiert und gehasht, das Objekt aufgeloest, Intent + Snapshot
    gebaut und `KomkiPolicy.Derive.decide/3` gestellt. Ein `deny` oder
    `indeterminate` tritt niemals als nackter Fehler auf, sondern als
    Remedy-Plan: die Ordnung der behebbaren Schritte IST die Antwort.
  * Tor 2 - Beweispruefung NACH dem Vollzug: das vollzogene Ergebnis wird
    gehasht und unabhaengig durch `KomkiPolicy.Verify.check/4` neu
    geprueft. Faellt die Pruefung aus, wird der Inhalt zurueckgehalten
    (`"admitted" => "redacted"`); der Modellkontext sieht dann nie den
    unbelegten Payload.
  * Jeder Ablauf haengt EINEN PDR-Auditdatensatz an (synchron via Journal)
    und bettet die `decision_id` in die Antwort ein - zitierfaehig.

  Entwurfsentscheidung (bestaetigt, RFC 0003 R.4.4): `payload_hash` bindet
  die Bytes, die die MCP-Schicht wirklich zurueckgibt (den Modellkontext),
  nicht den ungefilterten Connector-Payload: im Admitted-Fall wird das
  Vollzugsergebnis vor dem Zusammenmischen gehasht, im Rueckhalte-Fall die
  Rueckhalte-Antwort selbst.
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
  # Tor 1: Aufruf, Intent/Snapshot, Entscheidung
  # -------------------------------------------------------------------------

  @doc "Vermittelt einen Toolaufruf: Entscheidung, Vollzug, Rueckhaltung, PDR."
  @spec call(env(), String.t(), %{String.t() => term()}, executor()) :: map()
  def call(env, tool, params, executor) when is_binary(tool) and is_map(params) do
    intent_hash = Hash.sha256_hex(JSON.canonical(%{"tool" => tool, "params" => params}))

    case Room.object_for_call(env.room, tool, params) do
      {:ok, object} ->
        decide(env, tool, intent_hash, object, executor)

      {:error, :unknown_object, object_id} ->
        unknown_object(env, tool, intent_hash, object_id)
    end
  end

  # -------------------------------------------------------------------------
  # Tor 2: Vollzug und unabhaengige Beweispruefung
  # -------------------------------------------------------------------------

  @doc """
  Tor 2: unterwirft das Vollzugsergebnis der unabhaengigen Beweispruefung.
  Beweis klar durchgereicht (`valid`) -> Admit (markieren); verworfen ->
  Rueckhaltung (filtern); Executor-Fehler -> `admitted: false`. In allen
  Faellen: PDR.
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
        # Markieren: Ergebnis mit Entscheidungslabels versehen; der
        # payload_hash gilt dem vollzogenen Ergebnis (RFC R.4.4).
        payload_hash = Hash.sha256_hex(JSON.canonical(result))

        response =
          Map.merge(result, %{
            "decision" => "permit",
            "decision_id" => decision_id,
            "labels" => decision["checked_label"],
            "payload_hash" => payload_hash
          })

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

      {:ok, %{"result" => "invalid", "reasons" => reasons}} ->
        redact(env, tool, intent_hash, decision_id, reasons)

      {:error, err} ->
        redact(env, tool, intent_hash, decision_id, [error_detail(err)])
    end
  end

  defp redact(env, tool, intent_hash, decision_id, verify_reasons) do
    # Rueckhaltung: kein Ergebnisinhalt tritt raus. Der payload_hash bindet
    # die Rueckhalte-Antwort jenseits seines eigenen Feldes - genau die
    # Bytes, die der Modellkontext zu sehen bekommt.
    core = %{
      "decision" => "permit",
      "admitted" => "redacted",
      "decision_id" => decision_id,
      "reason" => "unabhaengige Beweispruefung fehlgeschlagen",
      "verify" => verify_reasons
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
