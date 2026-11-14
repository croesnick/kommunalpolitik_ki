defmodule RatsprojekteWeb.HubComponents do
  @moduledoc """
  The pieces the hub's pages share: the header, the dialog frame, the
  main flow „Was ist passiert?“, the next-step fields and the tally bar.
  """

  use RatsprojekteWeb, :html

  alias Ratsprojekte.Labels
  alias RatsprojekteWeb.Hub

  @doc "Page frame: header with the hub's name, the areas, today and „Neue Idee“."
  attr(:flash, :map, required: true)
  attr(:today, Date, required: true)
  attr(:current, :atom, default: :overview, values: [:overview, :briefing])
  slot(:inner_block, required: true)

  def hub(assigns) do
    ~H"""
    <header class="hub-kopf">
      <.link navigate={~p"/"} class="hub-marke">Ratsprojekte</.link>
      <nav class="hub-nav" aria-label="Bereiche">
        <.link navigate={~p"/"} aria-current={@current == :overview && "page"}>Übersicht</.link>
        <.link navigate={~p"/stand"} aria-current={@current == :briefing && "page"}>Stand</.link>
      </nav>
      <div class="ml-auto flex items-center gap-3">
        <span class="text-sm text-base-content/60">{Calendar.strftime(@today, "%d.%m.%Y")}</span>
        <.link navigate={~p"/?neu"} id="neue-idee" class="btn btn-primary btn-sm">Neue Idee</.link>
        <Layouts.theme_toggle />
      </div>
    </header>
    <main class="hub-main">
      {render_slot(@inner_block)}
    </main>
    <Layouts.flash_group flash={@flash} />
    """
  end

  @doc "A modal dialog around a form; Escape and „Abbrechen“ send `close`."
  attr(:id, :string, required: true)
  attr(:title, :string, required: true)
  attr(:subtitle, :string, default: nil)
  attr(:for, :any, required: true, doc: "the form")
  attr(:submit, :string, required: true)
  slot(:inner_block, required: true)

  def dialog(assigns) do
    ~H"""
    <div class="modal modal-open" role="dialog" aria-modal="true" aria-labelledby={"#{@id}-titel"}>
      <div class="modal-box max-w-xl" phx-window-keydown="close" phx-key="Escape">
        <h2 id={"#{@id}-titel"} class="hub-titel text-xl">{@title}</h2>
        <p :if={@subtitle} class="text-sm text-base-content/60 mt-0.5">{@subtitle}</p>
        <.form for={@for} id={@id} phx-change="validate" phx-submit="save" class="mt-3">
          {render_slot(@inner_block)}
          <div class="modal-action">
            <button type="button" class="btn" phx-click="close">Abbrechen</button>
            <button type="submit" class="btn btn-primary" phx-disable-with="Speichert …">
              {@submit}
            </button>
          </div>
        </.form>
      </div>
      <div class="modal-backdrop" phx-click="close"></div>
    </div>
    """
  end

  @doc """
  The fields of the main flow: who spoke, what came out (the only
  required field), who may read it (always visible), and folded away
  phase, next step and date. `motion` adds status and outcome.
  """
  attr(:form, Phoenix.HTML.Form, required: true)
  attr(:phase, :atom, required: true, doc: "the project's current phase")
  attr(:motion, :boolean, default: false)
  attr(:open, :boolean, default: false, doc: "show the folded part open")

  def event_fields(assigns) do
    ~H"""
    <div :if={@motion} class="grid grid-cols-2 gap-3">
      <.input
        field={@form[:status]}
        type="select"
        label="Status"
        options={options(Labels.motion_statuses())}
      />
      <.input
        field={@form[:outcome]}
        type="select"
        label="Ergebnis"
        prompt="noch keins"
        options={options(Labels.outcomes())}
      />
      <.input field={@form[:submitted_on]} type="date" label="Eingereicht am" />
      <.input field={@form[:report_due_on]} type="date" label="Bericht fällig bis" />
    </div>
    <.input :if={@motion} field={@form[:ris]} label="Sitzung und TOP" />
    <.input
      field={@form[:by]}
      type="select"
      label={if @motion, do: "Wer hat entschieden?", else: "Wer hat sich geäußert oder entschieden?"}
      prompt="Niemand Bestimmtes"
      options={options(Labels.actors())}
    />
    <.input
      field={@form[:text]}
      type="textarea"
      label={if @motion, do: "Was ist passiert?", else: "Was kam heraus?"}
      rows="3"
      phx-mounted={JS.focus()}
    />
    <fieldset class="fieldset" id="sichtbarkeit">
      <legend class="fieldset-legend">Wer darf das lesen?</legend>
      <label class="label text-base-content">
        <input
          type="radio"
          class="radio radio-sm"
          name={@form[:in_briefing].name}
          value="true"
          checked={to_string(@form[:in_briefing].value) != "false"}
        /> Fraktion und Vorstand, steht im Stand
      </label>
      <label class="label text-base-content">
        <input
          type="radio"
          class="radio radio-sm"
          name={@form[:in_briefing].name}
          value="false"
          checked={to_string(@form[:in_briefing].value) == "false"}
        /> Nur ich
      </label>
    </fieldset>
    <details class="hub-mehr" open={@open}>
      <summary>Hat sich dadurch etwas geändert?</summary>
      <.input
        field={@form[:phase]}
        type="select"
        label="Phase danach"
        options={phase_options(@phase)}
      />
      <p class="text-xs text-base-content/60 -mt-1 mb-2">Ein Phasenwechsel steht immer im Stand.</p>
      <.step_fields
        text={@form[:step_text]}
        assignee={@form[:step_assignee]}
        due_on={@form[:step_due_on]}
      />
      <.input field={@form[:on]} type="date" label="Wann war das?" />
    </details>
    """
  end

  @doc "Next step: what, who, by when. Shared by the main flow and the step dialog."
  attr(:text, Phoenix.HTML.FormField, required: true)
  attr(:assignee, Phoenix.HTML.FormField, required: true)
  attr(:due_on, Phoenix.HTML.FormField, required: true)

  def step_fields(assigns) do
    ~H"""
    <.input field={@text} label="Als Nächstes" />
    <p class="text-xs text-base-content/60 -mt-1 mb-2">
      Steht im Stand. Kein Name von Bürgerinnen und Bürgern, nichts Vertrauliches. Leer heißt: kein nächster Schritt.
    </p>
    <div class="grid grid-cols-2 gap-3">
      <.input field={@assignee} label="Wer?" placeholder="du, Selin, Vorstand …" />
      <.input field={@due_on} type="date" label="Bis wann?" />
    </div>
    """
  end

  @doc "The tally of an opinion as a bar with counts per level."
  attr(:tally, :list, required: true)

  def tally(assigns) do
    assigns = assign(assigns, :levels, Enum.zip(Hub.levels(), assigns.tally))

    ~H"""
    <div
      class="hub-vert"
      role="img"
      aria-label={Enum.map_join(@levels, ", ", fn {{_, word}, n} -> "#{word} #{n}" end)}
    >
      <i
        :for={{{{_, word}, n}, i} <- Enum.with_index(@levels, 1)}
        :if={n > 0}
        class={"stufe-#{i}"}
        style={"flex: #{n}"}
        title={"#{word}: #{n}"}
      ></i>
    </div>
    <div class="text-xs text-base-content/60 mt-0.5">
      {Enum.sum(@tally)} Personen: {Enum.map_join(@levels, " · ", fn {{sign, _}, n} ->
        "#{sign} #{n}"
      end)}
    </div>
    """
  end

  @doc "Options for a select from a label group."
  @spec options([{atom(), String.t()}]) :: [{String.t(), String.t()}]
  def options(pairs), do: Enum.map(pairs, fn {key, name} -> {name, to_string(key)} end)

  defp phase_options(current) do
    Enum.map(Labels.phases(), fn {key, name} ->
      {if(key == current, do: "#{name} (bleibt)", else: name), to_string(key)}
    end)
  end
end
