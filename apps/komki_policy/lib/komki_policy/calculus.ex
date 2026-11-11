defmodule KomkiPolicy.Calculus do
  @moduledoc """
  Reine Kalkuel-Funktionen auf der kompilierten Registry (RFC 5.2, § 4.3).

  Hier leben die mengenwertigen Grundgroessen des Policy-Kerns als
  oeffentliche, deterministische, seiteneffektfreie Funktionen — von
  `derive` fuer die Pruefung und den Beweisbaum benutzt und von `verify`
  (Phase 3a) fuer die unabhaengige Neuberechnung (CONTRACT.md § 5):

  * `allowed_recipients/2` — R_G(B_W): Durchschnitt der `readers`-Mengen
    aller geprueften Bindungen; bei B_W = [] gilt R_G(∅) = O, der komplette
    Registry-Beobachterraum (CONTRACT.md § 4.3 Punkt 8).
  * `actual_recipients/2` — r_G(c): sortierte `observers`-Liste der
    Verarbeitungsumgebung (CONTRACT.md § 2.2).
  * `labels_subset?/2` — l(x) Teilmenge B_W (Praemisse 7).
  * `lockerungsbeduerftige_bindungen/3` und `lockerungsbefugte/4` — die
    Mengenseite der Lockerung (R.5.7, § 4.9, Ticket #423): welche
    Bindungen das Ziel nicht abdecken und wer sie alle lockern darf.
  """

  alias KomkiPolicy.Registry

  @type checked_label() :: [String.t()]

  @doc "R_G(B_W): Durchschnitt aller readers; leeres Prueflabel = ganzer Beobachterraum O."
  @spec allowed_recipients(Registry.compiled(), checked_label()) :: [String.t()]
  def allowed_recipients(registry, []) do
    registry.observers
  end

  def allowed_recipients(registry, binding_ids) when is_list(binding_ids) do
    binding_ids
    |> Enum.map(&readers_of(registry, &1))
    |> Enum.reduce(&MapSet.intersection/2)
    |> MapSet.to_list()
    |> Enum.sort()
  end

  @doc "r_G(c): die sortierte Beobachterliste der Verarbeitungsumgebung."
  @spec actual_recipients(Registry.compiled(), String.t()) :: [String.t()]
  def actual_recipients(registry, environment_id) do
    env = Map.fetch!(registry.environments, environment_id)
    Enum.sort(env.observers)
  end

  @doc "l(x) Teilmenge B_W als Mengenpruefung (Sortierung ist gleichgueltig)."
  @spec labels_subset?([String.t()], checked_label()) :: boolean()
  def labels_subset?(object_labels, checked) do
    MapSet.subset?(MapSet.new(object_labels), MapSet.new(checked))
  end

  defp readers_of(registry, binding_id) do
    binding = Map.fetch!(registry.bindings, binding_id)
    MapSet.new(binding.readers)
  end

  @doc """
  Bindungen, deren Empfängerkreis `rho` nicht abdeckt (§ 4.9, R.5.7):
  nur für diese braucht eine Lockerung auf ein weiteres Ziel eine
  Befugnis — das Entfernen einer Bindung, die das Ziel ohnehin lesen
  durfte, lockert nichts. Ohne Eintrag ist keine Lockerung zulässig
  (R.2.2), deshalb entscheidet diese Menge, ob ein Fenster erscheint
  (Gegenprobe 13.1).
  """
  @spec lockerungsbeduerftige_bindungen(Registry.compiled(), checked_label(), [String.t()]) :: [
          String.t()
        ]
  def lockerungsbeduerftige_bindungen(registry, checked, rho) do
    Enum.filter(checked, fn binding_id ->
      case Map.get(registry.bindings, binding_id) do
        nil -> true
        binding -> rho -- binding.readers != []
      end
    end)
  end

  @doc """
  Autoritäten, die alle lockerungsbedürftigen Bindungen für die Ausgabeart
  `ausgabeart` lockern dürfen (§ 2.8, § 4.9): Schnittmenge der Befugnisse
  je Bindung. Nur wenn sie nicht leer ist, bietet der Katalog einer
  `store`-Ablehnung eine Offenlegungsfreigabe an — sonst würde das Fenster
  ein GO verlangen, das niemand erteilen kann.
  """
  @spec lockerungsbefugte(Registry.compiled(), checked_label(), [String.t()], String.t()) :: [
          String.t()
        ]
  def lockerungsbefugte(registry, checked, rho, ausgabeart) do
    registry
    |> lockerungsbeduerftige_bindungen(checked, rho)
    |> Enum.map(fn binding_id ->
      registry.bindings
      |> Map.get(binding_id)
      |> Map.get(:relaxation_authorities)
      |> Kernel.||([])
      |> Enum.filter(&(&1.restriction == "readers" and &1.output == ausgabeart))
      |> Enum.map(& &1.authority)
      |> MapSet.new()
    end)
    |> case do
      [] ->
        # Fail-closed: ohne lockerungsbedürftige Bindung gibt es keine
        # Lockerung, die eine Offenlegungsfreigabe decken könnte.
        []

      authorities ->
        authorities
        |> Enum.reduce(&MapSet.intersection/2)
        |> MapSet.to_list()
        |> Enum.sort()
    end
  end
end
