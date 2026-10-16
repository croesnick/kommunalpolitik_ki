defmodule KomkiMediator.Remedy do
  @moduledoc """
  Remedy-Plaene: Abhilfe statt nacktem `deny`. Aus den deterministischen
  Blockern bzw. den fehlenden Belegen einer Ableitung entsteht eine
  geordnete Liste behebbarer Schritte (aufzaehlbare rechtliche
  Fortfuehrungen statt blanker Verbotskommunikation). Die Plaene entstehen
  NUR hier im Vermittler — komki_policy bleibt ein reiner Pruefkern ohne
  Remedy-Modul.
  """

  alias KomkiMediator.Gamma

  @typedoc "Abhilfe-Eintrag: Typ, was er beheben kann, Relaxationsbefugnis."
  @type remedy() :: %{
          required(String.t()) => String.t() | nil
        }

  @doc """
  Bildet den Remedy-Plan einer Entscheidung. Bei `deny` werden die
  `blockers` abgearbeitet, bei `indeterminate` die `missing_evidence`.
  Deterministische Ordnung byteweise nach `{type, clears}`.
  """
  @spec from_decision(map(), Gamma.t()) :: [remedy()]
  def from_decision(decision, gamma) do
    entries =
      case decision["decision"] do
        "deny" -> List.wrap(decision["blockers"])
        "indeterminate" -> List.wrap(decision["missing_evidence"])
        _ -> []
      end

    entries
    |> Enum.map(&remedy_for(&1, gamma))
    |> Enum.reject(&is_nil/1)
    |> Enum.sort_by(&{&1["type"], &1["clears"]})
  end

  @doc "Vereinigte Relaxationsautoritaeten aller Plaene, sortiert und einmalig."
  @spec relaxation_authorities([remedy()]) :: [String.t()]
  def relaxation_authorities(remedies) do
    remedies
    |> Enum.flat_map(fn remedy -> List.wrap(remedy["relaxation_authorities"]) end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  # -------------------------------------------------------------------------
  # Geschlossene Abbildung Blocker/Belege zu Abhilfe
  # -------------------------------------------------------------------------

  defp remedy_for(
         %{"code" => "binding_condition_false", "binding" => binding, "condition" => condition},
         gamma
       ),
       do: remedy("provide_fact", condition, gamma, binding)

  defp remedy_for(%{"code" => "missing_operation_rule", "binding" => binding}, gamma),
    do: remedy("register_operation_rule", binding, gamma, binding)

  defp remedy_for(%{"code" => "object_quarantine", "binding" => binding}, gamma),
    do: remedy("unquarantine_object", binding, gamma, binding)

  defp remedy_for(%{"code" => "workspace_invalid", "binding" => binding}, gamma),
    do: remedy("repair_workspace", binding, gamma, binding)

  defp remedy_for(%{"code" => "basis_right_false", "binding" => binding}, gamma),
    do: remedy("restore_basis_right", binding, gamma, binding)

  defp remedy_for(%{"code" => "audit_path_not_ready", "binding" => binding}, gamma),
    do: remedy("restore_audit_path", binding, gamma, binding)

  defp remedy_for(%{"code" => "label_not_included", "binding" => binding}, gamma),
    do: remedy("extend_workspace_bindings", binding, gamma, binding)

  defp remedy_for(%{"code" => "recipient_not_allowed", "binding" => binding}, gamma),
    do: remedy("adjust_recipients", binding, gamma, binding)

  defp remedy_for(%{"code" => "missing_fact", "fact" => fact, "binding" => binding}, gamma),
    do: remedy("provide_fact", fact, gamma, binding)

  defp remedy_for(
         %{"code" => "recipients_unproven", "fact" => fact, "binding" => binding},
         gamma
       ),
       do: remedy("provide_recipient_proof", fact, gamma, binding)

  defp remedy_for(_unknown_entry, _gamma), do: nil

  defp remedy(type, clears, gamma, binding) do
    %{
      "type" => type,
      "clears" => clears,
      "relaxation_authorities" => Gamma.relaxation_authorities(gamma, binding)
    }
  end
end
