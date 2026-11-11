defmodule KomkiPolicy.Remedies do
  @moduledoc """
  Remedy catalog (CONTRACT.md § 2.8, APPA theorem 5).

  For every blocker and every missing piece of evidence a bounded,
  enumerable catalog of legal continuations made of **exactly five
  transition types** (enum values in German, as specified by the ticket):
  `fakt_nachreichen`, `registrierte_transformation`, `neuer_raum`,
  `aktionsfreigabe` and — since #423 — `offenlegungsfreigabe`.

  Normative order: `fakt_nachreichen` < `registrierte_transformation` <
  `neuer_raum` < `aktionsfreigabe` < `offenlegungsfreigabe` — non-violating
  continuations BEFORE GO entries; a GO never comes first (no
  "compensatory leakage"), the strongest GO last. The catalog is output
  only: no input accepts it, no continuation is executed, and it creates
  no authority (CONTRACT § 2.8, RFC 0003 R.6).

  Applicability (deny, § 2.8): the admit base table without a call GO;
  `emit`, `store` and `transfer` additionally get `aktionsfreigabe` scope
  `call` for the soft blockers. `workspace_invalid` and
  `label_not_preserved` (`store`, `transfer`) are unbridgeable and get
  `neuer_raum` only — a GO neither revives an invalid contract nor
  restores a dropped binding. For `store`, `recipient_not_allowed` is
  unbridgeable as well: a GO does not decide who may read the store
  (R.5.7, ticket #417). If an unbridgeable blocker is among the findings,
  no finding of that decision offers a call GO, since the release branch
  would deny it again. For `indeterminate` only `fakt_nachreichen` +
  `neuer_raum` — a GO cannot produce evidence. Release branch (§ 4.6):
  exactly one call-GO entry per release blocker with the **recomputed**
  correct call_hash; the unbridgeable blockers keep their `neuer_raum`
  entry.

  Offenlegungsfreigabe (§ 4.9, R.5.7, R.6.1, ticket #423): a `store`
  denial whose target lies outside the recipient circle gets exactly one
  working GO when every lockerungsbedürftige Bindung carries a matching
  Befugnis — an `offenlegungsfreigabe` scope `call` with the call hash,
  the Ausgabeart and the Ziellabel of the relaxation (R.6.2). It replaces
  the Aktionsfreigabe on the GO-fähigen findings of that decision: a
  plain Aktionsfreigabe could never bridge the recipient test (#417).
  Without the Befugnisse the catalog offers no GO at all (Gegenprobe
  13.1) — a window would ask for a GO that cannot take effect.
  """

  alias KomkiPolicy.Calculus
  alias KomkiPolicy.Registry

  @type rule_kind() :: :admit | :emit | :store | :transfer | :release

  # Rule branches with an output object: call GO in the catalog.
  @output_kinds [:emit, :store, :transfer]

  @unbridgeable ["workspace_invalid", "label_not_preserved"]

  # Blocker der Offenlegungsfreigabe (§ 4.9): keine Befugnis, kein
  # passendes Ziel, keine belegte Beobachterliste — all das überbrückt
  # auch kein GO, also bietet der Katalog keines an.
  @offenlegung_unbridgeable [
    "lockerungsbefugnis_fehlt",
    "ausgabeart_unpassend",
    "ziellabel_unknown",
    "ziellabel_unpassend",
    "recipients_unproven"
  ]

  # Operations whose recipient test no GO replaces (§ 4.7, R.5.7, #417). The
  # release branch re-checks the test for exactly these (Derive), so there
  # recipient_not_allowed is unbridgeable as well. For emit and transfer a
  # GO still bridges an inadmissible recipient (#354).
  @unbridgeable_recipient_operations ["store"]

  @doc "Operations for which no GO replaces the recipient test (§ 4.6, § 4.7, #417)."
  @spec unbridgeable_recipient_operations() :: [String.t()]
  def unbridgeable_recipient_operations, do: @unbridgeable_recipient_operations

  # Befunde, deren Fortsetzung ein GO für den exakten Call sein kann
  # (§ 2.8): nur diese kommen für die Ersetzung durch eine
  # Offenlegungsfreigabe in Frage.
  @call_go_codes [
    "basis_right_false",
    "binding_condition_false",
    "audit_path_not_ready",
    "recipient_not_allowed",
    "missing_operation_rule"
  ]

  @transition_order [
    "fakt_nachreichen",
    "registrierte_transformation",
    "neuer_raum",
    "aktionsfreigabe",
    "offenlegungsfreigabe"
  ]

  @type context() :: %{
          required(:rule) => rule_kind(),
          required(:object_labels) => [String.t()],
          required(:checked) => [String.t()],
          required(:rho) => [String.t()],
          required(:object_ref) => String.t(),
          required(:call_hash) => String.t() | nil,
          optional(:ausgabeart) => String.t() | nil,
          optional(:ziellabel) => [String.t()],
          optional(:release_kind) => String.t() | nil
        }

  @type finding() :: %{required(String.t()) => String.t() | nil}

  @doc """
  Builds the `remedies` list (deny shape: `code`/`binding`/`condition`/
  `transitions`; indeterminate shape: `code`/`fact`/`binding`/
  `transitions`) in the order of the given findings. A pure function of
  (registry, context, findings).
  """
  @spec catalog(Registry.compiled(), context(), [finding()]) :: [map()]

  # The context already carries `rule_kind` (`ctx.rule`); the catalog is a
  # pure function of (registry, context, findings).
  def catalog(registry, %{rule: rule_kind} = ctx, findings)
      when rule_kind in [:admit | @output_kinds] do
    findings
    |> Enum.map(fn finding ->
      Map.merge(finding, %{
        "transitions" => ordered(regular_transitions(registry, ctx, rule_kind, finding))
      })
    end)
    |> withhold_call_go(registry, ctx)
  end

  def catalog(_registry, %{rule: :release} = ctx, findings) do
    findings
    |> Enum.map(fn finding ->
      Map.merge(finding, %{"transitions" => ordered(release_transitions(ctx, finding))})
    end)
    |> withhold_call_go(nil, ctx)
  end

  # A GO never bridges the unbridgeable blockers; the release branch denies
  # them again. So no finding of such a decision may offer a call GO: the
  # person would be asked for a GO that cannot take effect (#298 review).
  # A finding left without transitions gets `neuer_raum`, so every
  # catalog entry stays non-empty. The one working GO on a `store`
  # denial with matching Befugnisse is the Offenlegungsfreigabe: sie
  # ersetzt dort die Aktionsfreigabe auf den GO-fähigen Befunden
  # (§ 2.8, § 4.9, Ticket #423).
  defp withhold_call_go(entries, registry, ctx) do
    codes = Enum.map(entries, & &1["code"])
    plan = go_plan(codes, registry, ctx)

    if plan == :keep do
      entries
    else
      Enum.map(entries, fn entry -> normalize_transitions(entry, ctx, plan) end)
    end
  end

  # Entscheidungsweite Planung (reine Funktion der Befunde): Was wird
  # gestrichen, was ersetzt? `:keep` laesst alles, wie es die
  # regular_transitions gebaut haben.
  defp go_plan(codes, registry, ctx) do
    strip_aktion? = Enum.any?(codes, &unbridgeable?(ctx.rule, &1))

    strip_offenlegung? = strip_offenlegung?(codes, ctx)

    offenlegung_instead? =
      ctx.rule == :store and "recipient_not_allowed" in codes and
        offenlegung_offerable?(registry, ctx) and not strip_offenlegung?

    if strip_aktion? or strip_offenlegung? or offenlegung_instead? do
      %{
        strip_aktion?: strip_aktion? or offenlegung_instead?,
        strip_offenlegung?: strip_offenlegung?,
        offenlegung_instead?: offenlegung_instead?
      }
    else
      :keep
    end
  end

  # Die Offenlegungsfreigabe wirkt nie bei harten Blockern — auch nicht
  # als Ersetzung: Der Freigabe-Zweig § 4.9 prueft dieselben Praemissen
  # erneut und wuerde das GO verweigern.
  defp strip_offenlegung?(codes, ctx) do
    Enum.any?(codes, &(&1 in @unbridgeable)) or
      Enum.any?(codes, &(&1 in @offenlegung_unbridgeable)) or
      (ctx.rule == :release and "recipient_not_allowed" in codes)
  end

  defp normalize_transitions(entry, ctx, plan) do
    transitions =
      entry["transitions"]
      |> strip_call_go("aktionsfreigabe", plan.strip_aktion?)
      |> strip_call_go("offenlegungsfreigabe", plan.strip_offenlegung?)
      |> maybe_offenlegung(instead?: plan.offenlegung_instead?, code: entry["code"], ctx: ctx)
      |> fill_neuer_raum(ctx)

    Map.put(entry, "transitions", transitions)
  end

  # Die Ersetzung: ein GO-fähiger Befund einer store-Ablehnung mit
  # unzulässigem Empfänger und passenden Befugnissen bekommt die
  # Offenlegungsfreigabe — sie deckt auch die fehlende Operationsregel
  # desselben Aufrufs (R.6.1: „Beide können in einer Transaktion
  # vorliegen").
  defp maybe_offenlegung(transitions, instead?: true, code: code, ctx: ctx)
       when code in @call_go_codes,
       do: transitions ++ [offenlegung_go(ctx)]

  defp maybe_offenlegung(transitions, _opts), do: transitions

  defp strip_call_go(transitions, _type, false), do: transitions

  defp strip_call_go(transitions, type, true),
    do: Enum.reject(transitions, &(&1["type"] == type and &1["scope"] == "call"))

  defp fill_neuer_raum([], ctx), do: [newer_space(ctx, required_bindings_for(ctx))]
  defp fill_neuer_raum(transitions, _ctx), do: transitions

  # Kann die Offenlegungsfreigabe für diesen Aufruf überhaupt wirken?
  # Nur bei store mit benannter Ausgabeart, Call-Hash und einer
  # nicht-leeren Schnittmenge der Befugnisse (§ 4.9) — sonst bliebe das
  # Fenster eine Frage, die niemand bejahen kann.
  defp offenlegung_offerable?(nil, _ctx), do: false

  defp offenlegung_offerable?(registry, ctx) do
    is_binary(ctx.ausgabeart) and ctx.call_hash != nil and
      Calculus.lockerungsbefugte(registry, ctx.checked, ctx.rho, ctx.ausgabeart) != []
  end

  # In the release branch, recipient_not_allowed only arises for the
  # operations above.
  defp unbridgeable?(:release, "recipient_not_allowed"), do: true

  defp unbridgeable?(rule, "recipient_not_allowed"),
    do: Atom.to_string(rule) in @unbridgeable_recipient_operations

  defp unbridgeable?(_rule, code), do: code in @unbridgeable

  # -------------------------------------------------------------------------
  # Transition building blocks (closed payload shapes, § 2.8)
  # -------------------------------------------------------------------------

  defp fakt(fact_names), do: %{"type" => "fakt_nachreichen", "facts" => fact_names}

  defp transformation(id, output_labels),
    do: %{
      "type" => "registrierte_transformation",
      "transformation" => id,
      "output_labels" => output_labels
    }

  defp newer_space(ctx, required_bindings),
    do: %{
      "type" => "neuer_raum",
      "required_bindings" => required_bindings,
      "required_recipients" => ctx.rho
    }

  defp call_go(call_hash),
    do: %{"type" => "aktionsfreigabe", "scope" => "call", "call_hash" => call_hash}

  # Die Offenlegungsfreigabe nennt, was das GO tragen muss (R.6.2: Zweck,
  # Ausgangs- und Ziellabel): Call-Hash, Ausgabeart und Ziellabel der
  # Lockerung.
  defp offenlegung_go(%{call_hash: call_hash, ausgabeart: ausgabeart, ziellabel: ziellabel}) do
    %{
      "type" => "offenlegungsfreigabe",
      "scope" => "call",
      "call_hash" => call_hash,
      "ausgabeart" => ausgabeart,
      "ziellabel" => ziellabel
    }
  end

  defp object_go(object_ref),
    do: %{"type" => "aktionsfreigabe", "scope" => "object", "object" => object_ref}

  # Order: the normative order, stable within each type (blocks appear in
  # construction order, transformations ascending by id). § 2.8 payload
  # rules: a `fakt_nachreichen` without a nameable field (facts: [] — e.g.
  # `binding_condition_false` with `condition: null`, a literal rule) is
  # dropped; there is nothing to supply with authority.
  defp ordered(transitions) do
    @transition_order
    |> Enum.flat_map(fn type ->
      Enum.filter(transitions, fn t -> Map.fetch!(t, "type") == type end)
    end)
    |> Enum.reject(&vacant_fakt?/1)
  end

  defp vacant_fakt?(%{"type" => "fakt_nachreichen", "facts" => facts}), do: facts == []
  defp vacant_fakt?(_transition), do: false

  # -------------------------------------------------------------------------
  # Applicability table (deny, § 2.8)
  # -------------------------------------------------------------------------

  defp regular_transitions(_registry, ctx, _kind, %{"code" => "object_quarantine"}),
    do: [object_go(ctx.object_ref)]

  # workspace_invalid and label_not_preserved: no GO entry, not even for
  # emit/store/transfer.
  defp regular_transitions(_registry, ctx, _kind, %{"code" => code})
       when code in @unbridgeable,
       do: [newer_space(ctx, required_bindings_for(ctx))]

  defp regular_transitions(_registry, ctx, kind, %{
         "code" => code,
         "condition" => condition
       })
       when code in ["basis_right_false", "binding_condition_false", "audit_path_not_ready"] do
    base = [fakt(facts_payload(condition)), newer_space(ctx, required_bindings_for(ctx))]

    if kind in @output_kinds and ctx.call_hash != nil do
      base ++ [call_go(ctx.call_hash)]
    else
      base
    end
  end

  defp regular_transitions(registry, ctx, _kind, %{"code" => "label_not_included"}) do
    matching_transformations(registry, ctx) ++ [newer_space(ctx, required_bindings_for(ctx))]
  end

  defp regular_transitions(_registry, ctx, kind, %{"code" => code})
       when code in ["recipient_not_allowed", "missing_operation_rule"] do
    if kind in @output_kinds and ctx.call_hash != nil do
      [newer_space(ctx, required_bindings_for(ctx)), call_go(ctx.call_hash)]
    else
      [newer_space(ctx, required_bindings_for(ctx))]
    end
  end

  # -------------------------------------------------------------------------
  # Applicability table (indeterminate, § 2.8): fakt_nachreichen +
  # neuer_raum — NEVER aktionsfreigabe (a GO cannot produce evidence).
  # -------------------------------------------------------------------------

  defp regular_transitions(
         _registry,
         ctx,
         _kind,
         %{"code" => code, "fact" => fact}
       ) do
    if code in ["missing_fact", "recipients_unproven"] do
      [fakt(facts_payload(fact)), newer_space(ctx, required_bindings_for(ctx))]
    else
      []
    end
  end

  defp regular_transitions(_registry, _ctx, _kind, _finding), do: []

  # -------------------------------------------------------------------------
  # Applicability table (release branch, § 4.6, § 4.9)
  # -------------------------------------------------------------------------

  # Offenlegungsfreigabe-Zweig: die Blocker, die auch das stärkste GO
  # nicht überbrückt, behalten nur `neuer_raum`; die übrigen Befunde
  # erhalten eine Offenlegungsfreigabe für den exakten Call mit neu
  # berechnetem Hash (§ 4.9) — die Person kann erneut freigeben.
  defp release_transitions(%{release_kind: "offenlegungsfreigabe"} = ctx, %{"code" => code})
       when code in @unbridgeable or code in @offenlegung_unbridgeable or
              code == "recipient_not_allowed",
       do: [newer_space(ctx, [])]

  defp release_transitions(%{release_kind: "offenlegungsfreigabe"} = ctx, _finding),
    do: [offenlegung_go(ctx)]

  defp release_transitions(ctx, %{"code" => code})
       when code in @unbridgeable,
       do: [newer_space(ctx, [])]

  defp release_transitions(%{call_hash: call_hash}, _finding),
    do: [call_go(call_hash)]

  # -------------------------------------------------------------------------
  # Payload helpers
  # -------------------------------------------------------------------------

  defp facts_payload(fact) when is_binary(fact), do: [fact]
  defp facts_payload(_), do: []

  # § 2.8 payload rules: `neuer_raum.required_bindings` = λ(x) for admit,
  # `[]` for emit, store and transfer (and in the release branch).
  defp required_bindings_for(%{rule: :admit, object_labels: object_labels}),
    do: Enum.sort(object_labels)

  defp required_bindings_for(_ctx), do: []

  defp matching_transformations(registry, ctx) do
    registry.transformations
    |> Enum.sort_by(fn {id, _t} -> id end)
    |> Enum.filter(fn {_id, t} ->
      Calculus.labels_subset?(t.input_labels, ctx.object_labels) and
        Calculus.labels_subset?(t.output_labels, ctx.checked)
    end)
    |> Enum.map(fn {id, t} -> transformation(id, t.output_labels) end)
  end
end
