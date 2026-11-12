defmodule Ratsprojekte.Projects do
  @moduledoc """
  The context of the small model (ADR 0004): Ratsprojekte with their
  timeline, opinions, facts, variants, motions and cross references.
  Callers get the domain without knowing the tables.

  The timeline writes itself: every function that changes something
  appends the line that says so. By hand comes only what happened
  elsewhere, through the main flow `record_event/2` („Was ist
  passiert?“) and its counterpart at a motion, `record_motion_event/3`.

  Every function that changes a project returns it freshly loaded with
  everything it carries.
  """

  import Ecto.Query, only: [from: 2]
  import Ecto.Changeset

  alias Ecto.Multi
  alias Ratsprojekte.{Labels, Repo, Text}

  alias Ratsprojekte.Projects.{
    CrossReference,
    Event,
    Fact,
    Motion,
    NextStep,
    Opinion,
    Project,
    TimelineEntry,
    Value,
    Variant
  }

  @preloads [:timeline, :opinions, :facts, :variants, :motions, :cross_references]

  @type result :: {:ok, Project.t()} | {:error, Ecto.Changeset.t()}

  ## Reading

  @doc "All projects with everything they carry, by title."
  @spec list_projects() :: [Project.t()]
  def list_projects do
    Repo.all(from(p in Project, order_by: [asc: p.title], preload: ^@preloads))
  end

  @doc "The project with this slug, or `nil`."
  @spec get_project(String.t()) :: Project.t() | nil
  def get_project(slug) do
    case Repo.get_by(Project, slug: slug) do
      nil -> nil
      project -> Repo.preload(project, @preloads)
    end
  end

  @doc "The project with this slug; raises if there is none."
  @spec get_project!(String.t()) :: Project.t()
  def get_project!(slug), do: Project |> Repo.get_by!(slug: slug) |> Repo.preload(@preloads)

  @doc "Today in local time: the date of entries without one."
  @spec today() :: Date.t()
  def today, do: :calendar.local_time() |> elem(0) |> Date.from_erl!()

  ## Projects

  @doc "Changeset for the form of a new idea."
  @spec change_project(Project.t(), map()) :: Ecto.Changeset.t()
  def change_project(project \\ %Project{}, attrs \\ %{}), do: Project.changeset(project, attrs)

  @doc """
  The short name a title suggests that no project carries yet
  (`radweg-bahnhofstrasse`, else `radweg-bahnhofstrasse-2`, …).
  """
  @spec suggest_slug(String.t() | nil) :: String.t()
  def suggest_slug(nil), do: ""

  def suggest_slug(title) do
    case Text.slugify(Text.clean(title)) do
      "" -> ""
      base -> Enum.find(Stream.concat([base], Stream.map(2..1000, &"#{base}-#{&1}")), &free?/1)
    end
  end

  defp free?(slug), do: not Repo.exists?(from(p in Project, where: p.slug == ^slug))

  @doc """
  A new idea: title, short text, origin and short name (suggested from
  the title if missing). Starts in phase Idee with „Idee aufgenommen“.
  """
  @spec create_project(map()) :: result()
  def create_project(attrs) do
    attrs = stringify(attrs)

    attrs =
      if blank?(attrs["slug"]),
        do: Map.put(attrs, "slug", suggest_slug(attrs["title"])),
        else: attrs

    Multi.new()
    |> Multi.insert(:project, Project.changeset(%Project{}, attrs))
    |> Multi.insert(:entry, fn %{project: project} ->
      entry(project, :created, "Idee aufgenommen", date(attrs))
    end)
    |> run(fn %{project: project} -> project end)
  end

  @doc "Changes title, short text or origin; the slug stays."
  @spec update_project(Project.t(), map()) :: result()
  def update_project(project, attrs) do
    attrs = attrs |> stringify() |> Map.delete("slug")

    project
    |> Project.changeset(attrs)
    |> Repo.update()
    |> reload()
  end

  ## Main flow

  @doc "Changeset for the form of the main flow."
  @spec change_event(map()) :: Ecto.Changeset.t()
  def change_event(attrs \\ %{}), do: Event.changeset(%Event{}, attrs)

  @doc """
  The main flow „Was ist passiert?“: appends an entry and takes a phase
  change and a new next step along.

  - Visibility: `in_briefing`, by default everything except what the
    editor alone („Nur ich“) noted.
  - Phase change: one decision entry „Alt → Neu: text“, always in the
    briefing.
  - A circle that spoke and may be read becomes an opinion of that circle.
  - Next step: only if the event carries the step fields, see `Event`.
  """
  @spec record_event(Project.t(), map()) :: result()
  def record_event(%Project{} = project, attrs) do
    attrs = stringify(attrs)

    with {:ok, event} <- apply_action(Event.changeset(%Event{}, attrs), :insert) do
      on = event.on || today()
      visible = if is_nil(event.in_briefing), do: event.by != :editor, else: event.in_briefing
      circle = if visible and event.by in Labels.keys(Labels.circles()), do: event.by

      Multi.new()
      |> maybe_opinion(project, circle, event.text, on)
      |> event_entry(project, event, on, visible, if(circle, do: :opinion, else: :note))
      |> project_changes(project, event.phase, step_from_event(event, attrs), on)
      |> run(fn _ -> project end)
    end
  end

  defp maybe_opinion(multi, _project, nil, _text, _on), do: multi

  defp maybe_opinion(multi, project, circle, text, on) do
    Multi.insert(multi, :opinion, %Opinion{
      project_id: project.id,
      on: on,
      circle: circle,
      statement: text
    })
  end

  # A phase change makes the entry a decision that always goes into the briefing.
  defp event_entry(multi, project, event, on, visible, kind) do
    if phase_change?(project, event.phase) do
      text = "#{phase_name(project.phase)} → #{phase_name(event.phase)}: #{event.text}"
      Multi.insert(multi, :entry, entry(project, :decision, text, on, by: event.by))
    else
      Multi.insert(
        multi,
        :entry,
        entry(project, kind, event.text, on, by: event.by, in_briefing: visible)
      )
    end
  end

  defp phase_change?(project, phase), do: not is_nil(phase) and phase != project.phase

  defp step_from_event(event, attrs) do
    cond do
      not Event.step_given?(attrs) -> :unchanged
      is_nil(event.step_text) -> nil
      true -> %{text: event.step_text, assignee: event.step_assignee, due_on: event.step_due_on}
    end
  end

  # Phase and next step in one update of the project; the next step
  # writes its own line when it really changed.
  defp project_changes(multi, project, phase, step, on) do
    step =
      if step != :unchanged and same_step?(project.next_step, step), do: :unchanged, else: step

    changeset =
      project
      |> change()
      |> then(&if phase_change?(project, phase), do: put_change(&1, :phase, phase), else: &1)
      |> then(&if step == :unchanged, do: &1, else: put_step(&1, step))

    multi
    |> then(&if changeset.changes == %{}, do: &1, else: Multi.update(&1, :project, changeset))
    |> then(fn multi ->
      if step == :unchanged,
        do: multi,
        else: Multi.insert(multi, :step_entry, entry(project, :next_step, step_line(step), on))
    end)
  end

  defp put_step(changeset, nil), do: put_embed(changeset, :next_step, nil)

  defp put_step(changeset, step),
    do: put_embed(changeset, :next_step, NextStep.changeset(%NextStep{}, step))

  defp same_step?(nil, nil), do: true
  defp same_step?(nil, _step), do: false
  defp same_step?(_current, nil), do: false

  defp same_step?(current, step),
    do:
      Map.take(current, [:text, :assignee, :due_on]) ==
        Map.take(step, [:text, :assignee, :due_on])

  defp step_line(nil), do: "Nächsten Schritt entfernt"

  defp step_line(step) do
    Enum.join(
      ["Als Nächstes: #{step.text}"] ++
        if(blank?(step.assignee), do: [], else: [step.assignee]) ++
        if(step.due_on, do: ["bis #{german_date(step.due_on)}"], else: []),
      ", "
    )
  end

  @doc "Changeset for the form of the next step."
  @spec change_next_step(Project.t(), map()) :: Ecto.Changeset.t()
  def change_next_step(project, attrs \\ %{}),
    do: NextStep.changeset(project.next_step || %NextStep{}, attrs)

  @doc "Sets the next step (`text`, `assignee`, `due_on`); an empty text removes it."
  @spec set_next_step(Project.t(), map()) :: result()
  def set_next_step(project, attrs) do
    attrs = stringify(attrs)

    with {:ok, step} <- next_step(attrs) do
      Multi.new() |> project_changes(project, nil, step, date(attrs)) |> run(fn _ -> project end)
    end
  end

  defp next_step(attrs) do
    if blank?(Text.clean(attrs["text"])) do
      {:ok, nil}
    else
      with {:ok, step} <- apply_action(NextStep.changeset(%NextStep{}, attrs), :insert),
           do: {:ok, Map.from_struct(step)}
    end
  end

  @doc """
  Switches whether a note goes into the briefing. Only notes: a decision
  or an opinion stays as it was entered.
  """
  @spec set_entry_visibility(Project.t(), integer(), boolean()) ::
          {:ok, Project.t()} | {:error, :not_found}
  def set_entry_visibility(project, entry_id, in_briefing) do
    query =
      from(e in TimelineEntry,
        where: e.id == ^entry_id and e.project_id == ^project.id and e.kind == :note
      )

    case Repo.update_all(query, set: [in_briefing: in_briefing]) do
      {1, _} -> {:ok, get_project!(project.slug)}
      {0, _} -> {:error, :not_found}
    end
  end

  ## Disposition

  @decision_types %{
    disposition: :string,
    status: :string,
    reason: :string,
    by: :string,
    on: :date
  }

  @doc "Changeset for the form of disposing or resuming a project."
  @spec change_decision(map()) :: Ecto.Changeset.t()
  def change_decision(attrs \\ %{}) do
    {%{}, @decision_types}
    |> cast(stringify(attrs), Map.keys(@decision_types))
    |> Text.clean_fields([:reason])
    |> validate_required([:reason])
    |> validate_length(:reason, max: 1000)
    |> validate_inclusion(:by, Enum.map(Labels.keys(Labels.actors()), &Atom.to_string/1))
  end

  @doc "Files the project away (`disposition`: resting, rejected, completed) with a reason."
  @spec dispose(Project.t(), map()) :: result()
  def dispose(project, attrs) do
    changeset =
      attrs
      |> change_decision()
      |> validate_required([:disposition])
      |> validate_inclusion(
        :disposition,
        Enum.map(Labels.keys(Labels.dispositions()), &Atom.to_string/1)
      )

    with {:ok, decision} <- apply_action(changeset, :insert) do
      disposition = String.to_existing_atom(decision.disposition)
      on = decision[:on] || today()
      by = actor(decision[:by])
      text = "#{Labels.name(Labels.dispositions(), disposition)}: #{decision.reason}"

      Multi.new()
      |> Multi.update(
        :project,
        project
        |> change(disposition: disposition, disposed_on: on)
        |> put_embed(:next_step, nil)
      )
      |> Multi.insert(:entry, entry(project, :decision, text, on, by: by))
      |> run(fn _ -> project end)
    end
  end

  @doc "Takes a filed project up again, with a reason."
  @spec resume(Project.t(), map()) :: result()
  def resume(project, attrs) do
    with {:ok, decision} <- apply_action(change_decision(attrs), :insert) do
      on = decision[:on] || today()

      Multi.new()
      |> Multi.update(:project, change(project, disposition: nil, disposed_on: nil))
      |> Multi.insert(
        :entry,
        entry(project, :decision, "Wieder aufgenommen: #{decision.reason}", on,
          by: actor(decision[:by])
        )
      )
      |> run(fn _ -> project end)
    end
  end

  ## Value, facts, variants, cross references

  @doc "Changeset for the form „Nutzen und Erfolg“."
  @spec change_value(Project.t(), map()) :: Ecto.Changeset.t()
  def change_value(project, attrs \\ %{}), do: Value.changeset(project.value || %Value{}, attrs)

  @doc "Sets benefit and success („Nutzen und Erfolg“)."
  @spec set_value(Project.t(), map()) :: result()
  def set_value(project, attrs) do
    attrs = stringify(attrs)
    value = change_value(project, attrs)

    cond do
      not value.valid? ->
        {:error, value}

      value.changes == %{} ->
        {:ok, project}

      true ->
        Multi.new()
        |> Multi.update(:project, project |> change() |> put_embed(:value, value))
        |> Multi.insert(:entry, entry(project, :value, "Nutzen und Erfolg geändert", date(attrs)))
        |> run(fn _ -> project end)
    end
  end

  @doc "Changeset for the form of a fact."
  @spec change_fact(map()) :: Ecto.Changeset.t()
  def change_fact(attrs \\ %{}), do: Fact.changeset(%Fact{}, attrs)

  @doc "Adds a fact with citation and date; `verified` says a person checked the source."
  @spec add_fact(Project.t(), map()) :: result()
  def add_fact(project, attrs) do
    attrs = stringify(attrs)

    Multi.new()
    |> Multi.insert(:fact, Fact.changeset(%Fact{project_id: project.id}, attrs))
    |> Multi.insert(:entry, fn %{fact: fact} ->
      entry(project, :fact, "Fakt ergänzt: #{fact.statement}", date(attrs))
    end)
    |> run(fn _ -> project end)
  end

  @doc "Changeset for the form of a variant, with the next free label."
  @spec change_variant(Project.t(), map()) :: Ecto.Changeset.t()
  def change_variant(project, attrs \\ %{}),
    do: Variant.changeset(%Variant{label: next_label(project), project_id: project.id}, attrs)

  defp next_label(project) do
    taken = MapSet.new(project.variants, & &1.label)
    Enum.find(Enum.map(?A..?Z, &<<&1>>), &(not MapSet.member?(taken, &1)))
  end

  @doc """
  Adds a variant. `prerequisites` is a list of `%{text, kind, met}`;
  a legal basis is a prerequisite of kind `legal`.
  """
  @spec add_variant(Project.t(), map()) :: result()
  def add_variant(project, attrs) do
    attrs = stringify(attrs)

    Multi.new()
    |> Multi.insert(:variant, change_variant(project, attrs))
    |> Multi.insert(:entry, fn %{variant: variant} ->
      entry(project, :variant, "Variante #{variant.label} ergänzt: #{variant.title}", date(attrs))
    end)
    |> run(fn _ -> project end)
  end

  @doc "Chooses or rejects a variant (`status`: chosen, rejected) with a reason."
  @spec decide_variant(Project.t(), String.t(), map()) :: result()
  def decide_variant(project, label, attrs) do
    variant = Enum.find(project.variants, &(&1.label == label)) || raise Ecto.NoResultsError

    changeset =
      attrs
      |> change_decision()
      |> validate_required([:status])
      |> validate_inclusion(:status, ["chosen", "rejected"])

    with {:ok, decision} <- apply_action(changeset, :insert) do
      status = String.to_existing_atom(decision.status)
      on = decision[:on] || today()
      verb = Labels.name(Labels.variant_statuses(), status)

      Multi.new()
      |> Multi.update(:variant, change(variant, status: status, reason: decision.reason))
      |> Multi.insert(
        :entry,
        entry(project, :decision, "Variante #{label} #{verb}: #{decision.reason}", on,
          by: actor(decision[:by])
        )
      )
      |> run(fn _ -> project end)
    end
  end

  @doc "Changeset for the form of a cross reference."
  @spec change_cross_reference(map()) :: Ecto.Changeset.t()
  def change_cross_reference(attrs \\ %{}), do: CrossReference.changeset(%CrossReference{}, attrs)

  @doc "Adds a cross reference (vault, filing, komki room); never in the briefing."
  @spec add_cross_reference(Project.t(), map()) :: result()
  def add_cross_reference(project, attrs) do
    attrs = stringify(attrs)

    Multi.new()
    |> Multi.insert(
      :reference,
      CrossReference.changeset(%CrossReference{project_id: project.id}, attrs)
    )
    |> Multi.insert(:entry, fn %{reference: reference} ->
      kind = Labels.name(Labels.cross_reference_kinds(), reference.kind)

      entry(project, :cross_reference, "Querverweis ergänzt: #{kind}", date(attrs),
        in_briefing: false
      )
    end)
    |> run(fn _ -> project end)
  end

  ## Motions

  @doc "Changeset for the form of a new motion."
  @spec change_motion(map()) :: Ecto.Changeset.t()
  def change_motion(attrs \\ %{}), do: Motion.changeset(%Motion{}, attrs)

  @doc "Starts a motion („Antrag beginnen“) as a draft."
  @spec create_motion(Project.t(), map()) :: result()
  def create_motion(project, attrs) do
    attrs = stringify(attrs)

    Multi.new()
    |> Multi.insert(:motion, Motion.changeset(%Motion{project_id: project.id}, attrs))
    |> Multi.insert(:entry, fn %{motion: motion} ->
      kind = Labels.name(Labels.motion_kinds(), motion.kind)
      entry(project, :motion, "#{kind} „#{motion.title}“ begonnen", date(attrs))
    end)
    |> run(fn _ -> project end)
  end

  @doc """
  The main flow at a motion: status, outcome, dates and session in one
  step with what happened, who decided, the phase after and the next
  step. Same rules as `record_event/2`, without an opinion; a missing
  `status` keeps the current one.
  """
  @spec record_motion_event(Project.t(), Motion.t(), map()) :: result()
  def record_motion_event(%Project{} = project, %Motion{} = motion, attrs) do
    attrs = stringify(attrs)

    with {:ok, event} <- apply_action(Event.changeset(%Event{}, attrs), :insert) do
      on = event.on || today()

      progress =
        event |> Event.motion_attrs() |> Map.reject(fn {k, v} -> k == :status and is_nil(v) end)

      kind = if event.by, do: :decision, else: :motion

      Multi.new()
      |> Multi.update(:motion, Motion.progress_changeset(motion, progress))
      |> event_entry(project, event, on, true, kind)
      |> project_changes(project, event.phase, step_from_event(event, attrs), on)
      |> run(fn _ -> project end)
    end
  end

  ## Helpers

  defp entry(project, kind, text, on, opts \\ []) do
    %TimelineEntry{
      project_id: project.id,
      kind: kind,
      text: text,
      on: on,
      by: Keyword.get(opts, :by),
      in_briefing: Keyword.get(opts, :in_briefing, true)
    }
  end

  # Runs the multi and returns the project (picked from the results)
  # freshly loaded; a failed step returns its changeset.
  defp run(multi, pick) do
    case Repo.transaction(multi) do
      {:ok, results} -> {:ok, get_project!(pick.(results).slug)}
      {:error, _step, %Ecto.Changeset{} = changeset, _done} -> {:error, changeset}
    end
  end

  defp reload({:ok, project}), do: {:ok, get_project!(project.slug)}
  defp reload(error), do: error

  defp date(attrs) do
    case attrs["on"] do
      %Date{} = date ->
        date

      text when is_binary(text) ->
        case Date.from_iso8601(text) do
          {:ok, date} -> date
          {:error, _} -> today()
        end

      _ ->
        today()
    end
  end

  defp actor(nil), do: nil
  defp actor(""), do: nil
  defp actor(by), do: String.to_existing_atom(by)

  defp phase_name(phase), do: Labels.name(Labels.phases(), phase)

  @doc false
  @spec german_date(Date.t()) :: String.t()
  def german_date(date), do: Calendar.strftime(date, "%d.%m.%Y")

  defp blank?(value), do: is_nil(value) or value == ""

  defp stringify(attrs), do: Map.new(attrs, fn {k, v} -> {to_string(k), v} end)
end
