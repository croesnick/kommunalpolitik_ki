defmodule RatsprojekteWeb.Hub do
  @moduledoc """
  What the work view derives from a project, without touching it: German
  dates and names, deadline markers, who has been heard, the checklist
  „Antragsreife“. Pure functions over the structs `Ratsprojekte.Projects`
  returns.

  The person who runs the hub is „ich“ in the data (`NextStep`) and
  „Du“ on the screen.
  """

  alias Ratsprojekte.Labels
  alias Ratsprojekte.Projects.{NextStep, Project}

  @doc "Is the editor meant?"
  @spec self?(String.t() | nil) :: boolean()
  def self?(name), do: NextStep.editor?(name)

  @doc "The assignee as the work view says it: „Du“ for the editor."
  @spec assignee(String.t() | nil) :: String.t() | nil
  def assignee(name), do: if(self?(name), do: "Du", else: name)

  @doc "The assignee as a form field shows it: „du“ for the editor."
  @spec assignee_input(String.t() | nil) :: String.t() | nil
  def assignee_input(name), do: if(self?(name), do: "du", else: name)

  @doc "`03.11.2026`; within the current year `03.11.`."
  @spec date(Date.t() | nil, Date.t()) :: String.t()
  def date(nil, _today), do: ""

  def date(date, today) do
    if date.year == today.year,
      do: Calendar.strftime(date, "%d.%m."),
      else: Calendar.strftime(date, "%d.%m.%Y")
  end

  @doc "The German name of a phase, disposition, actor, … within its group."
  @spec name(atom(), atom() | nil) :: String.t()
  def name(_group, nil), do: ""
  def name(group, key), do: Labels.name(apply(Labels, group, []), key)

  @doc "Questions the board asks per phase."
  @spec phase_question(atom()) :: String.t()
  def phase_question(:idea), do: "Wollen wir darüber reden?"
  def phase_question(:opinion_forming), do: "Wollen wir das wirklich?"
  def phase_question(:drafting), do: "Wie genau, und geht das?"
  def phase_question(:at_council), do: "Was macht der Rat daraus?"
  def phase_question(:implementation), do: "Passiert es auch?"

  @doc """
  The deadline marker of the next step: `{:overdue, "Überfällig"}`, or
  within seven days `{:soon, "Heute" | "Morgen" | "In N Tagen"}`, else nil.
  """
  @spec deadline(Project.t(), Date.t()) :: {:overdue | :soon, String.t()} | nil
  def deadline(%Project{disposition: nil, next_step: %{due_on: %Date{} = due}}, today) do
    case Date.diff(due, today) do
      days when days < 0 -> {:overdue, "Überfällig"}
      0 -> {:soon, "Heute"}
      1 -> {:soon, "Morgen"}
      days when days <= 7 -> {:soon, "In #{days} Tagen"}
      _ -> nil
    end
  end

  def deadline(_project, _today), do: nil

  @doc "Last day something happened."
  @spec last_activity(Project.t()) :: Date.t() | nil
  def last_activity(project) do
    project.timeline |> Enum.map(& &1.on) |> Enum.max(Date, fn -> nil end)
  end

  @doc """
  Weeks a project has been lying: nothing happened for four weeks AND
  nothing is agreed with a date. Whoever waits for an appointment does
  not lie.
  """
  @spec lying_weeks(Project.t(), Date.t()) :: pos_integer() | nil
  def lying_weeks(%Project{disposition: nil} = project, today) do
    last = last_activity(project)
    agreed = project.next_step && project.next_step.due_on

    if last && !agreed && Date.diff(today, last) > 28,
      do: div(Date.diff(today, last), 7)
  end

  def lying_weeks(_project, _today), do: nil

  @doc "Does the project need attention (deadline near or past, or lying)?"
  @spec attention?(Project.t(), Date.t()) :: boolean()
  def attention?(project, today),
    do: deadline(project, today) != nil or lying_weeks(project, today) != nil

  @doc "Is the next step the editor's?"
  @spec mine?(Project.t()) :: boolean()
  def mine?(project), do: project.next_step != nil and self?(project.next_step.assignee)

  @doc "The latest opinion of a circle, or nil."
  @spec latest_opinion(Project.t(), atom()) :: map() | nil
  def latest_opinion(project, circle) do
    project.opinions
    |> Enum.filter(&(&1.circle == circle))
    |> Enum.max_by(&{&1.on, &1.id}, fn -> nil end)
  end

  @doc """
  The circles a card shows: Fraktion, Vorstand, Basis always, Externe
  only once heard; each with whether it has been heard.
  """
  @spec heard(Project.t()) :: [{atom(), String.t(), boolean()}]
  def heard(project) do
    for {circle, name} <- Labels.circles(),
        heard <- [latest_opinion(project, circle) != nil],
        circle != :external or heard,
        do: {circle, name, heard}
  end

  @doc "The five levels of a tally, from „klar dagegen“ to „klar dafür“."
  @spec levels() :: [{String.t(), String.t()}]
  def levels,
    do: [
      {"––", "klar dagegen"},
      {"–", "eher dagegen"},
      {"○", "neutral"},
      {"+", "eher dafür"},
      {"++", "klar dafür"}
    ]

  @doc """
  The checklist „Antragsreife“: it locks nothing (ADR 0004). Each item is
  `{text, :ok | :open | :hint}`.
  """
  @spec maturity(Project.t()) :: [{String.t(), :ok | :open | :hint}]
  def maturity(project) do
    value = project.value || %{proposition: nil, success_metrics: nil}
    motion = Enum.find(project.motions, &(&1.status in [:draft, :in_fraction]))
    chosen = Enum.find(project.variants, &(&1.status == :chosen))

    [
      {"Was ändert sich, für wen?", ok_if(filled?(value.proposition))},
      {"Woran messen wir den Erfolg?", ok_if(filled?(value.success_metrics))},
      motion_item(motion),
      {"Adressat steht fest", ok_if(motion != nil and filled?(motion.addressee))},
      facts_item(project.facts),
      variants_item(project.variants, chosen),
      prerequisites_item(project.variants, chosen),
      fraction_item(project.timeline)
    ]
  end

  defp motion_item(nil), do: {"Noch kein Antrag begonnen", :open}

  defp motion_item(motion),
    do: {"Beschlussvorschlag ist konkret", ok_if(filled?(motion.motion_text))}

  defp facts_item(facts) do
    count = length(facts)
    unchecked = Enum.count(facts, &(!&1.verified))
    base = "#{count} #{if count == 1, do: "Fakt", else: "Fakten"} mit Beleg"
    text = if unchecked > 0, do: "#{base}, #{unchecked} nicht verifiziert", else: base
    {text, ok_if(count > 0 and unchecked == 0)}
  end

  defp prerequisites_item(variants, chosen) do
    considered = if chosen, do: [chosen], else: Enum.reject(variants, &(&1.status == :rejected))
    open = considered |> Enum.flat_map(& &1.prerequisites) |> Enum.count(&(!&1.met))

    case open do
      0 -> {"Keine offenen Vorbedingungen", :ok}
      1 -> {"1 offene Vorbedingung", :open}
      n -> {"#{n} offene Vorbedingungen", :open}
    end
  end

  defp fraction_item(timeline) do
    if Enum.any?(timeline, &(&1.kind == :decision and &1.by == :fraction)),
      do: {"Fraktion hat sich festgelegt", :ok},
      else: {"Keine Festlegung der Fraktion eingetragen", :hint}
  end

  defp variants_item([], _chosen),
    do: {"Keine Varianten, bei einfachen Anträgen in Ordnung", :hint}

  defp variants_item(_variants, nil), do: {"Noch keine Variante gewählt", :open}
  defp variants_item(_variants, chosen), do: {"Variante #{chosen.label} gewählt", :ok}

  defp ok_if(true), do: :ok
  defp ok_if(_), do: :open

  defp filled?(text), do: is_binary(text) and String.trim(text) != ""
end
