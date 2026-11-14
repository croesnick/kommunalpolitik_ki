defmodule Ratsprojekte.Labels do
  @moduledoc """
  German names for the atoms of the model (#414: code English, domain
  German). The timeline writes these names into its entries, the
  interface shows them; one place keeps both in step.
  """

  @phases [
    idea: "Idee",
    opinion_forming: "Meinungsbildung",
    drafting: "Ausarbeitung",
    at_council: "Im Rat",
    implementation: "Umsetzung"
  ]

  @dispositions [resting: "Ruht", rejected: "Verworfen", completed: "Abgeschlossen"]

  @actors [
    fraction: "Fraktion",
    board: "Vorstand",
    base: "Basis",
    external: "Externe",
    council: "Stadtrat",
    editor: "Nur ich"
  ]

  @circles [fraction: "Fraktion", board: "Vorstand", base: "Basis", external: "Externe"]

  @motion_kinds [motion: "Antrag", inquiry: "Anfrage", urgent_motion: "Dringlichkeitsantrag"]

  @motion_statuses [
    draft: "Entwurf",
    in_fraction: "In der Fraktion",
    submitted: "Eingereicht",
    deliberated: "Beraten"
  ]

  @outcomes [
    adopted: "Angenommen",
    adopted_amended: "Geändert angenommen",
    rejected: "Abgelehnt",
    deferred: "Vertagt",
    withdrawn: "Zurückgezogen"
  ]

  @variant_statuses [open: "offen", chosen: "gewählt", rejected: "verworfen"]

  @cross_reference_kinds [vault: "Vault", filing: "Ablage", komki_room: "Recherche in komki"]

  @prerequisite_kinds [legal: "Rechtsgrundlage", knowledge: "Voraussetzung"]

  @survey_statuses [preparing: "In Vorbereitung", running: "Läuft", answered: "Beantwortet"]

  for {name, pairs} <- [
        phases: @phases,
        dispositions: @dispositions,
        actors: @actors,
        circles: @circles,
        motion_kinds: @motion_kinds,
        motion_statuses: @motion_statuses,
        outcomes: @outcomes,
        variant_statuses: @variant_statuses,
        cross_reference_kinds: @cross_reference_kinds,
        prerequisite_kinds: @prerequisite_kinds,
        survey_statuses: @survey_statuses
      ] do
    @doc "Atoms and German names, in display order."
    @spec unquote(name)() :: [{atom(), String.t()}]
    def unquote(name)(), do: unquote(pairs)
  end

  @doc "The atoms of a group, for `Ecto.Enum`."
  @spec keys([{atom(), String.t()}]) :: [atom()]
  def keys(pairs), do: Keyword.keys(pairs)

  @doc "The German name of `key` within `pairs`."
  @spec name([{atom(), String.t()}], atom()) :: String.t()
  def name(pairs, key), do: Keyword.fetch!(pairs, key)
end
