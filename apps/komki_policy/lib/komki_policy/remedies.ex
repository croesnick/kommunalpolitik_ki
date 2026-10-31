defmodule KomkiPolicy.Remedies do
  @moduledoc """
  Remedy-Katalog (CONTRACT.md § 2.8, APPA Theorem 5).

  Zu jedem Blocker und jedem fehlenden Beleg ein begrenzter,
  aufzählbarer Katalog legaler Fortsetzungen aus **genau vier
  Übergangstypen** (Enum-Werte nach Ticketvorgabe deutsch):
  `fakt_nachreichen`, `registrierte_transformation`, `neuer_raum`,
  `aktionsfreigabe`.

  Normative Ordnung: `fakt_nachreichen` < `registrierte_transformation` <
  `neuer_raum` < `aktionsfreigabe` — nicht-verletzende Fortsetzungen VOR
  GO-Einträgen; ein GO steht nie an erster Stelle (kein "compensatory
  leakage"). Der Katalog ist reine Ausgabe: keine Eingabe akzeptiert ihn,
  keine Fortsetzung wird ausgeführt; er erzeugt keine Autorität
  (CONTRACT § 2.8, RFC 0003 R.6).

  Anwendbarkeit (deny, § 2.8): admit-Grundtabelle ohne call-GO; `emit`,
  `store` und `transfer` zusätzlich `aktionsfreigabe` scope `call` für die fünf weichen Blocker
  (`workspace_invalid` bleibt unüberbrückbar — ein GO belebt keinen
  ungültigen Vertrag). Für `indeterminate` nur `fakt_nachreichen` +
  `neuer_raum` — ein GO kann keine Belege herstellen. Freigabe-Zweig
  (§ 4.6): je Release-Blocker genau ein call-GO-Eintrag mit dem **neu
  berechneten** korrekten call_hash; `workspace_invalid` behält seinen
  `neuer_raum`-Eintrag. `label_not_preserved` (`store`, `transfer`) bekommt nur
  `neuer_raum`, auch im Freigabe-Zweig: ein GO stellt keine entfernte
  Bindung wieder her.
  """

  alias KomkiPolicy.Calculus
  alias KomkiPolicy.Registry

  @type rule_kind() :: :admit | :emit | :store | :transfer | :release

  # Regelzweige mit Ausgabeobjekt: call-GO im Katalog.
  @output_kinds [:emit, :store, :transfer]

  @unbridgeable ["workspace_invalid", "label_not_preserved"]

  @transition_order [
    "fakt_nachreichen",
    "registrierte_transformation",
    "neuer_raum",
    "aktionsfreigabe"
  ]

  @type context() :: %{
          required(:rule) => rule_kind(),
          required(:object_labels) => [String.t()],
          required(:checked) => [String.t()],
          required(:rho) => [String.t()],
          required(:object_ref) => String.t(),
          required(:call_hash) => String.t() | nil
        }

  @type finding() :: %{required(String.t()) => String.t() | nil}

  @doc """
  Baut die `remedies`-Liste (deny-Form: `code`/`binding`/`condition`/
  `transitions`; indeterminate-Form: `code`/`fact`/`binding`/
  `transitions`) in derselben Ordnung wie die übergebenen Befunde. Reine
  Funktion von (registry, context, finding-Liste).
  """
  @spec catalog(Registry.compiled(), context(), [finding()]) :: [map()]

  # `rule_kind` trägt der Kontext bereits (`ctx.rule`); der Katalog ist reine
  # Funktion von (registry, context, finding-Liste).
  def catalog(registry, %{rule: rule_kind} = ctx, findings)
      when rule_kind in [:admit | @output_kinds] do
    ctx = withhold_call_go(ctx, findings)

    Enum.map(findings, fn finding ->
      Map.merge(finding, %{
        "transitions" => ordered(regular_transitions(registry, ctx, rule_kind, finding))
      })
    end)
  end

  def catalog(_registry, %{rule: :release} = ctx, findings) do
    Enum.map(findings, fn finding ->
      Map.merge(finding, %{"transitions" => ordered(release_transitions(ctx, finding))})
    end)
  end

  # A GO never bridges these blockers; the release branch denies them again.
  # So no other finding of the same decision may offer a call GO either:
  # the person would be asked for a GO that cannot take effect (#298 review).
  defp withhold_call_go(ctx, findings) do
    if Enum.any?(findings, &(&1["code"] in @unbridgeable)),
      do: %{ctx | call_hash: nil},
      else: ctx
  end

  # -------------------------------------------------------------------------
  # Übergangs-Bausteine (geschlossene Payload-Formen § 2.8)
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

  defp object_go(object_ref),
    do: %{"type" => "aktionsfreigabe", "scope" => "object", "object" => object_ref}

  # Ordnung: normative Reihenfolge, stabil innerhalb jedes Typs (die
  # Bausteine erscheinen in ihrer Konstruktionsordnung, Transformationen
  # aufsteigend nach Kennung). § 2.8 Payload-Regeln: ein
  # `fakt_nachreichen` ohne benennbares Feld (facts: [] — z. B.
  # `binding_condition_false` bei `condition: null`, Literal-Regel)
  # entfällt; es gibt nichts autoritativ nachzureichen.
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
  # Anwendbarkeitstabelle (deny, § 2.8)
  # -------------------------------------------------------------------------

  defp regular_transitions(_registry, ctx, _kind, %{"code" => "object_quarantine"}),
    do: [object_go(ctx.object_ref)]

  # workspace_invalid: kein GO-Eintrag, auch nicht bei emit/store/transfer;
  # label_not_preserved ebenso.
  defp regular_transitions(_registry, ctx, _kind, %{"code" => code})
       when code in ["workspace_invalid", "label_not_preserved"],
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
  # Anwendbarkeitstabelle (indeterminate, § 2.8): fakt nachreichen +
  # neuer_raum — NIE aktionsfreigabe (ein GO kann keine Belege herstellen).
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
  # Anwendbarkeitstabelle (Freigabe-Zweig, § 4.6)
  # -------------------------------------------------------------------------

  defp release_transitions(ctx, %{"code" => code})
       when code in ["workspace_invalid", "label_not_preserved"],
       do: [newer_space(ctx, [])]

  defp release_transitions(%{call_hash: call_hash}, _finding),
    do: [call_go(call_hash)]

  # -------------------------------------------------------------------------
  # Payload-Helfer
  # -------------------------------------------------------------------------

  defp facts_payload(fact) when is_binary(fact), do: [fact]
  defp facts_payload(_), do: []

  # § 2.8 Payload-Regeln: `neuer_raum.required_bindings` = λ(x) bei admit,
  # `[]` bei emit, store und transfer (und im Freigabe-Zweig).
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
