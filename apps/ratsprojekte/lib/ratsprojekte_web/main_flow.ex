defmodule RatsprojekteWeb.MainFlow do
  @moduledoc """
  The form behind „Was ist passiert?“, shared by the overview and the
  project page: what the dialog starts with, how it reacts while typing,
  and what goes to `Projects.record_event/2` or, at a motion,
  `Projects.record_motion_event/3`.

  The step fields start with the current next step, so an untouched
  dialog changes nothing about it.
  """

  alias Ratsprojekte.Projects
  alias Ratsprojekte.Projects.{Motion, Project}
  alias RatsprojekteWeb.Hub

  @doc "Params the dialog opens with; `phase` preselects a phase change."
  @spec initial(Project.t(), keyword()) :: map()
  def initial(project, opts \\ []) do
    step = project.next_step || %{text: nil, assignee: nil, due_on: nil}

    Map.merge(
      %{
        "text" => "",
        "by" => "",
        "in_briefing" => "true",
        "phase" => to_string(Keyword.get(opts, :phase) || project.phase),
        "on" => Date.to_iso8601(Projects.today()),
        "step_text" => step.text,
        "step_assignee" => Hub.assignee_input(step.assignee),
        "step_due_on" => step.due_on && Date.to_iso8601(step.due_on)
      },
      motion_initial(Keyword.get(opts, :motion))
    )
  end

  defp motion_initial(nil), do: %{}

  defp motion_initial(%Motion{} = motion) do
    %{
      "status" => to_string(motion.status),
      "outcome" => motion.outcome && to_string(motion.outcome),
      "submitted_on" => motion.submitted_on && Date.to_iso8601(motion.submitted_on),
      "report_due_on" => motion.report_due_on && Date.to_iso8601(motion.report_due_on),
      "ris" => motion.ris
    }
  end

  @doc "The form for `params`; with `action`, errors show."
  @spec form(map(), atom() | nil) :: Phoenix.HTML.Form.t()
  def form(params, action \\ nil) do
    params
    |> Projects.change_event()
    |> Map.put(:action, action)
    |> Phoenix.Component.to_form(as: :event)
  end

  @doc """
  While typing: whoever picks „Nur ich“ as the one who spoke gets
  „Nur ich“ as readers too; the choice stays visible and can be changed.
  """
  @spec validate(map(), map()) :: map()
  def validate(params, previous) do
    if params["by"] == "editor" and previous["by"] != "editor",
      do: Map.put(params, "in_briefing", "false"),
      else: params
  end

  @doc "Records the event at the project, or at the motion if one is given."
  @spec save(Project.t(), Motion.t() | nil, map()) ::
          {:ok, Project.t()} | {:error, Ecto.Changeset.t()}
  def save(project, motion, params) do
    case motion do
      nil -> Projects.record_event(project, params)
      motion -> Projects.record_motion_event(project, motion, params)
    end
  end
end
