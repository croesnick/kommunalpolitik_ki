defmodule RatsprojekteWeb.ProjectLive do
  @moduledoc """
  One project: phase, next step, opinions, facts, variants, motions,
  benefit, and the timeline with „Neuer Eintrag“. Every change goes
  through a context function of `Ratsprojekte.Projects`, which also
  writes the timeline line; this view only collects the input.

  The main flow „Was ist passiert?“ carries phase and next step along;
  clicking a phase opens it with that phase preselected, because a phase
  change needs a reason in the timeline. At a motion the same dialog
  carries status and outcome.
  """

  use RatsprojekteWeb, :live_view

  import RatsprojekteWeb.HubComponents

  alias Ratsprojekte.{Labels, Projects}
  alias RatsprojekteWeb.{Hub, MainFlow}

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    case Projects.get_project(slug) do
      nil ->
        {:ok,
         socket |> put_flash(:error, "Dieses Projekt gibt es nicht.") |> push_navigate(to: ~p"/")}

      project ->
        {:ok,
         assign(socket,
           project: project,
           page_title: project.title,
           today: Projects.today(),
           dialog: nil,
           form: nil,
           params: %{},
           motion: nil,
           label: nil,
           open_more: false
         )}
    end
  end

  ## Dialogs: which one, which form, what saving does

  @impl true
  def handle_event("open", %{"dialog" => dialog} = values, socket) do
    {:noreply, open(socket, dialog, values)}
  end

  def handle_event("close", _params, socket), do: {:noreply, close(socket)}

  def handle_event("validate", params, socket) do
    {dialog, as} = socket.assigns.dialog
    input = Map.get(params, as, %{})

    input =
      if dialog in [:event, :motion_event],
        do: MainFlow.validate(input, socket.assigns.params),
        else: input

    {:noreply, assign(socket, params: input, form: form(socket, dialog, input, :validate))}
  end

  def handle_event("save", params, socket) do
    {dialog, as} = socket.assigns.dialog

    case save(socket, dialog, Map.get(params, as, %{})) do
      {:ok, project} ->
        {:noreply,
         socket
         |> close()
         |> assign(project: project, page_title: project.title)
         |> put_flash(:info, "Gespeichert")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(%{changeset | action: :insert}, as: as))}
    end
  end

  def handle_event("sichtbarkeit", %{"id" => id, "in" => in_briefing}, socket) do
    {:ok, project} =
      Projects.set_entry_visibility(
        socket.assigns.project,
        String.to_integer(id),
        in_briefing == "true"
      )

    {:noreply, assign(socket, project: project)}
  end

  defp open(socket, "event", values) do
    phase = Enum.find(Labels.keys(Labels.phases()), &(to_string(&1) == values["phase"]))
    params = MainFlow.initial(socket.assigns.project, phase: phase)

    socket
    |> assign(dialog: {:event, "event"}, params: params, open_more: phase != nil)
    |> assign(form: MainFlow.form(params))
  end

  defp open(socket, "motion_event", %{"id" => id}) do
    motion = Enum.find(socket.assigns.project.motions, &(to_string(&1.id) == id))
    params = MainFlow.initial(socket.assigns.project, motion: motion)

    socket
    |> assign(dialog: {:motion_event, "event"}, motion: motion, params: params, open_more: true)
    |> assign(form: MainFlow.form(params))
  end

  defp open(socket, "variant_decide", %{"label" => label, "status" => status})
       when status in ["chosen", "rejected"] do
    params = %{"status" => status, "by" => "fraction"}

    socket
    |> assign(dialog: {:variant_decide, "decision"}, label: label, params: params)
    |> assign(form: form(socket, :variant_decide, params, nil))
  end

  defp open(socket, dialog, _values)
       when dialog in ~w(next_step motion fact variant cross_reference value dispose resume) do
    dialog = String.to_existing_atom(dialog)
    params = start_params(socket.assigns.project, dialog)

    socket
    |> assign(dialog: {dialog, form_name(dialog)}, params: params)
    |> assign(form: form(socket, dialog, params, nil))
  end

  defp close(socket), do: assign(socket, dialog: nil, form: nil, params: %{}, open_more: false)

  defp form_name(:next_step), do: "step"
  defp form_name(:motion), do: "motion"
  defp form_name(:fact), do: "fact"
  defp form_name(:variant), do: "variant"
  defp form_name(:cross_reference), do: "reference"
  defp form_name(:value), do: "value"
  defp form_name(dialog) when dialog in [:dispose, :resume], do: "decision"

  defp start_params(project, :next_step) do
    step = project.next_step || %{text: nil, assignee: nil, due_on: nil}

    %{
      "text" => step.text,
      "assignee" => Hub.assignee_input(step.assignee),
      "due_on" => step.due_on
    }
  end

  defp start_params(_project, :motion), do: %{"kind" => "motion", "addressee" => "Stadtrat"}

  defp start_params(_project, :fact),
    do: %{"fetched_on" => Date.to_iso8601(Projects.today()), "verified" => "true"}

  defp start_params(_project, :cross_reference), do: %{"kind" => "filing"}

  defp start_params(project, :value) do
    value = project.value || %{proposition: nil, success_metrics: nil}
    %{"proposition" => value.proposition, "success_metrics" => value.success_metrics}
  end

  defp start_params(_project, :dispose), do: %{"disposition" => "resting", "by" => "fraction"}
  defp start_params(_project, :resume), do: %{"by" => "fraction"}
  defp start_params(_project, _dialog), do: %{}

  defp form(_socket, dialog, params, action) when dialog in [:event, :motion_event],
    do: MainFlow.form(params, action)

  defp form(socket, dialog, params, action) do
    project = socket.assigns.project

    changeset =
      case dialog do
        :next_step -> Projects.change_next_step(project, params)
        :motion -> Projects.change_motion(params)
        :fact -> Projects.change_fact(params)
        :variant -> Projects.change_variant(project, params)
        :cross_reference -> Projects.change_cross_reference(params)
        :value -> Projects.change_value(project, params)
        _decision -> Projects.change_decision(params)
      end

    to_form(%{changeset | action: action}, as: form_name_for(dialog))
  end

  defp form_name_for(:variant_decide), do: "decision"
  defp form_name_for(dialog), do: form_name(dialog)

  defp save(socket, :event, params), do: MainFlow.save(socket.assigns.project, nil, params)

  defp save(socket, :motion_event, params),
    do: MainFlow.save(socket.assigns.project, socket.assigns.motion, params)

  defp save(socket, :variant, params),
    do: Projects.add_variant(socket.assigns.project, variant_params(params))

  defp save(socket, :variant_decide, params),
    do: Projects.decide_variant(socket.assigns.project, socket.assigns.label, params)

  @savers %{
    next_step: :set_next_step,
    motion: :create_motion,
    fact: :add_fact,
    cross_reference: :add_cross_reference,
    value: :set_value,
    dispose: :dispose,
    resume: :resume
  }

  defp save(socket, dialog, params),
    do: apply(Projects, Map.fetch!(@savers, dialog), [socket.assigns.project, params])

  # The form has one field for a legal basis and one for another
  # prerequisite; the model keeps both as prerequisites.
  defp variant_params(params) do
    prerequisites =
      [{"legal", params["legal_basis"]}, {"knowledge", params["prerequisite"]}]
      |> Enum.reject(fn {_kind, text} -> text in [nil, ""] end)
      |> Enum.map(fn {kind, text} -> %{"kind" => kind, "text" => text} end)

    Map.put(params, "prerequisites", prerequisites)
  end

  ## Page

  @impl true
  def render(assigns) do
    assigns =
      assign(assigns,
        later: assigns.project.phase in [:drafting, :at_council, :implementation],
        phase_index: Enum.find_index(Labels.phases(), fn {k, _} -> k == assigns.project.phase end)
      )

    ~H"""
    <.hub flash={@flash} today={@today}>
      <div class="hub-seite">
        <div class="min-w-0">
          <.link navigate={~p"/"} class="link link-primary text-sm">Zur Übersicht</.link>
          <h1 class="hub-titel text-3xl mt-1" id="titel">{@project.title}</h1>
          <p :if={@project.short} class="text-base-content/80 mt-1">{@project.short}</p>

          <div :if={@project.disposition} class="alert alert-info mt-3" id="abgelegt">
            <span>
              {Hub.name(:dispositions, @project.disposition)} seit {Hub.date(@project.disposed_on, @today)}.
            </span>
            <button type="button" class="btn btn-sm" phx-click="open" phx-value-dialog="resume">
              Wieder aufnehmen
            </button>
          </div>

          <div class="hub-phasen" role="group" aria-label="Phase" id="phasen">
            <button
              :for={{{key, name}, i} <- Enum.with_index(Labels.phases())}
              type="button"
              phx-click="open"
              phx-value-dialog="event"
              phx-value-phase={key}
              class={[i < @phase_index && "war", i == @phase_index && "jetzt"]}
              aria-current={if i == @phase_index, do: "step"}
              title={if i != @phase_index, do: "Nach „#{name}“ wechseln, mit Grund im Verlauf"}
            >
              {name}
            </button>
          </div>

          <div class="hub-naechst" id="naechster-schritt">
            <span class="text-sm text-base-content/60">Als Nächstes</span>
            <%= if @project.next_step do %>
              <span class="font-semibold">{@project.next_step.text}</span>
              <span class="text-sm text-base-content/70">
                {Hub.assignee(@project.next_step.assignee)}{if @project.next_step.due_on,
                  do: " · bis #{Hub.date(@project.next_step.due_on, @today)}"}
              </span>
              <.deadline project={@project} today={@today} />
            <% else %>
              <span class="text-sm text-base-content/60">Noch nichts festgelegt</span>
            <% end %>
            <button
              type="button"
              class="btn btn-ghost btn-sm text-primary ml-auto"
              phx-click="open"
              phx-value-dialog="next_step"
            >
              Ändern
            </button>
          </div>

          <button
            type="button"
            id="neuer-eintrag-oben"
            class="btn btn-primary w-full mt-3 lg:hidden"
            phx-click="open"
            phx-value-dialog="event"
          >
            Neuer Eintrag
          </button>

          <%= if @later do %>
            <.motions project={@project} today={@today} />
            <.value project={@project} />
            <.facts project={@project} today={@today} />
            <.variants project={@project} always />
            <.opinions project={@project} today={@today} />
          <% else %>
            <.opinions project={@project} today={@today} />
            <.facts project={@project} today={@today} />
            <.variants project={@project} always={false} />
            <.motions :if={@project.motions != []} project={@project} today={@today} />
          <% end %>
        </div>

        <aside class="min-w-0">
          <section :if={@project.phase == :drafting and !@project.disposition} class="hub-block mt-0" id="antragsreife">
            <h2>Antragsreife <span class="text-xs font-normal text-base-content/60">Checkliste, sperrt nichts</span></h2>
            <ul class="mt-1">
              <li :for={{text, state} <- Hub.maturity(@project)} class="flex gap-2 py-0.5 text-sm">
                <span class={["hub-check", "hub-check-#{state}"]} aria-hidden="true">
                  {case state do
                    :ok -> "✓"
                    :open -> "!"
                    :hint -> "·"
                  end}
                </span>
                <span>{text}</span>
              </li>
            </ul>
          </section>

          <section class="hub-block" id="verlauf">
            <h2>Verlauf</h2>
            <p class="text-sm text-base-content/60 mt-1">
              Was du hier im Hub tust, steht von selbst darin. Was anderswo passiert ist, trägst du ein.
            </p>
            <button
              type="button"
              id="neuer-eintrag"
              class="btn btn-primary w-full mt-2"
              phx-click="open"
              phx-value-dialog="event"
            >
              Neuer Eintrag
            </button>
            <ol class="hub-verlauf">
              <li
                :for={entry <- Enum.reverse(@project.timeline)}
                id={"eintrag-#{entry.id}"}
                class={entry.kind == :decision && "entscheidung"}
              >
                <small>
                  {Hub.date(entry.on, @today)}{if entry.by && entry.by != :editor,
                    do: " · #{Hub.name(:actors, entry.by)}"}
                  <span :if={!entry.in_briefing} class="badge badge-ghost badge-xs ml-1">nur für mich</span>
                  <button
                    :if={entry.kind == :note}
                    type="button"
                    class="link link-primary text-xs ml-1"
                    phx-click="sichtbarkeit"
                    phx-value-id={entry.id}
                    phx-value-in={to_string(!entry.in_briefing)}
                  >
                    {if entry.in_briefing, do: "aus dem Stand nehmen", else: "in den Stand"}
                  </button>
                </small>
                <span class="whitespace-pre-line">{entry.text}</span>
              </li>
            </ol>
          </section>

          <details class="hub-block hub-mehr" id="querverweise">
            <summary>Querverweise ({1 + length(@project.cross_references) + if(@project.origin, do: 1, else: 0)})</summary>
            <p class="text-sm mt-1 flex items-center gap-2">
              Im Vault: <code id="vault-tag">#ratsprojekt/{@project.slug}</code>
              <button
                type="button"
                id="tag-kopieren"
                class="btn btn-ghost btn-xs text-primary"
                phx-hook=".Kopieren"
                data-text={"#ratsprojekt/#{@project.slug}"}
              >
                Kopieren
              </button>
            </p>
            <p :for={ref <- @project.cross_references} class="text-sm mt-1">
              {Hub.name(:cross_reference_kinds, ref.kind)}: <span class="break-all">{ref.target}</span>
            </p>
            <p :if={@project.origin} class="text-sm mt-1">Herkunft: {@project.origin}</p>
            <button
              type="button"
              class="link link-primary text-sm mt-2"
              phx-click="open"
              phx-value-dialog="cross_reference"
            >
              Querverweis ergänzen
            </button>
          </details>

          <div :if={!@project.disposition} class="hub-block">
            <button type="button" class="link link-primary text-sm" phx-click="open" phx-value-dialog="dispose">
              Projekt ablegen
            </button>
          </div>
        </aside>
      </div>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".Kopieren">
        export default {
          mounted() {
            this.el.addEventListener("click", () => {
              navigator.clipboard.writeText(this.el.dataset.text).then(() => {
                const before = this.el.textContent
                this.el.textContent = "Kopiert"
                setTimeout(() => { this.el.textContent = before }, 1500)
              })
            })
          }
        }
      </script>

      <.dialogs
        dialog={@dialog}
        form={@form}
        project={@project}
        motion={@motion}
        label={@label}
        open_more={@open_more}
      />
    </.hub>
    """
  end

  ## Blocks

  attr(:project, :map, required: true)
  attr(:today, Date, required: true)

  defp opinions(assigns) do
    ~H"""
    <section class="hub-block" id="meinungsbild">
      <h2>Meinungsbild</h2>
      <div :for={{name, opinion} <- opinion_rows(@project)} class={["hub-mb", !opinion && "leer"]}>
        <div class="font-semibold">
          {name}
          <small :if={opinion} class="block font-normal text-xs text-base-content/60">
            {Hub.date(opinion.on, @today)}
          </small>
        </div>
        <div :if={!opinion} class="text-base-content/60">Noch nicht gehört</div>
        <div :if={opinion}>
          <div :if={opinion.question} class="text-sm text-base-content/60">{opinion.question}</div>
          <div :if={opinion.statement}>{opinion.statement}</div>
          <.tally :if={opinion.tally} tally={opinion.tally} />
        </div>
      </div>
    </section>
    """
  end

  defp opinion_rows(project) do
    for {circle, name, _heard} <- Hub.heard(project),
        do: {name, Hub.latest_opinion(project, circle)}
  end

  attr(:project, :map, required: true)
  attr(:today, Date, required: true)

  defp facts(assigns) do
    ~H"""
    <section class="hub-block" id="fakten">
      <h2>
        Fakten
        <button type="button" class="hub-aktion" phx-click="open" phx-value-dialog="fact">Ergänzen</button>
      </h2>
      <p :if={@project.facts == []} class="text-sm text-base-content/60 mt-1">
        Noch nichts belegt. Fakten dürfen in jeder Phase kommen.
      </p>
      <div :for={fact <- @project.facts} class="hub-zeile" id={"fakt-#{fact.id}"}>
        <div>{fact.statement}</div>
        <div class="text-sm text-base-content/60">
          {fact.citation}, {Hub.date(fact.fetched_on, @today)}
          <a :if={fact.url} href={fact.url} class="link link-primary" rel="noopener noreferrer" target="_blank">Link</a>
          ·
          <span :if={fact.verified} class="text-success font-semibold">geprüft</span>
          <span :if={!fact.verified} class="text-warning font-semibold">nicht verifiziert</span>
        </div>
      </div>
    </section>
    """
  end

  attr(:project, :map, required: true)
  attr(:always, :boolean, required: true)

  defp variants(assigns) do
    ~H"""
    <section :if={@always or @project.variants != []} class="hub-block" id="varianten">
      <h2>
        Varianten
        <button type="button" class="hub-aktion" phx-click="open" phx-value-dialog="variant">Ergänzen</button>
      </h2>
      <p :if={@project.variants == []} class="text-sm text-base-content/60 mt-1">
        Keine. Das ist bei einfachen Anträgen in Ordnung.
      </p>
      <div :for={variant <- @project.variants} class="hub-zeile" id={"variante-#{variant.label}"}>
        <div class="flex flex-wrap items-baseline gap-2">
          <b class={variant.status == :rejected && "line-through text-base-content/50"}>
            {variant.label} · {variant.title}
          </b>
          <span :if={variant.status != :open} class={["badge badge-sm badge-soft", variant.status == :chosen && "badge-success"]}>
            {Hub.name(:variant_statuses, variant.status)}
          </span>
          <span :if={variant.status == :open} class="ml-auto flex gap-2">
            <button
              type="button"
              class="link link-primary text-sm"
              phx-click="open"
              phx-value-dialog="variant_decide"
              phx-value-label={variant.label}
              phx-value-status="chosen"
            >
              Wählen
            </button>
            <button
              type="button"
              class="link link-primary text-sm"
              phx-click="open"
              phx-value-dialog="variant_decide"
              phx-value-label={variant.label}
              phx-value-status="rejected"
            >
              Verwerfen
            </button>
          </span>
        </div>
        <div class="text-sm text-base-content/60">
          {[variant.description | Enum.map(variant.prerequisites, &"#{if &1.met, do: "✓", else: "○"} #{&1.text}")]
          |> Kernel.++([variant.reason])
          |> Enum.reject(&(&1 in [nil, ""]))
          |> Enum.join(" · ")}
        </div>
      </div>
    </section>
    """
  end

  attr(:project, :map, required: true)
  attr(:today, Date, required: true)

  defp motions(assigns) do
    ~H"""
    <section class="hub-block" id="antraege">
      <h2>
        Anträge
        <button type="button" class="hub-aktion" phx-click="open" phx-value-dialog="motion">Antrag beginnen</button>
      </h2>
      <p :if={@project.motions == []} class="text-sm text-base-content/60 mt-1">Noch kein Antrag.</p>
      <article :for={motion <- @project.motions} class="hub-antrag" id={"antrag-#{motion.id}"}>
        <div class="flex flex-wrap items-baseline gap-2">
          <b>{motion.title}</b>
          <span class="text-sm text-base-content/60">{Hub.name(:motion_kinds, motion.kind)}</span>
          <span :if={motion.outcome} class={["badge badge-sm badge-soft", motion.outcome in [:adopted, :adopted_amended] && "badge-success"]}>
            {Hub.name(:outcomes, motion.outcome)}
          </span>
          <button
            type="button"
            class="btn btn-ghost btn-sm text-primary ml-auto"
            phx-click="open"
            phx-value-dialog="motion_event"
            phx-value-id={motion.id}
          >
            Aktualisieren
          </button>
        </div>
        <ol class="hub-stufen" aria-label="Status">
          <li
            :for={{{key, name}, i} <- Enum.with_index(Labels.motion_statuses())}
            class={status_class(i, Labels.motion_statuses(), motion.status)}
            aria-current={if key == motion.status, do: "step"}
          >
            {name}
          </li>
        </ol>
        <p :if={motion.motion_text} class="text-sm mt-2">
          <b>Beschlussvorschlag:</b> {motion.motion_text}
          <span :if={motion.addressee} class="text-base-content/60">An: {motion.addressee}</span>
        </p>
        <p :if={motion.document_ref} class="text-sm mt-1">Text liegt hier: <span class="break-all">{motion.document_ref}</span></p>
        <p :if={motion.submitted_on} class="text-sm mt-1">
          Eingereicht am {Hub.date(motion.submitted_on, @today)}{if motion.ris, do: " · #{motion.ris}"}
        </p>
        <p :if={motion.report_due_on} class="text-sm mt-1">Bericht fällig bis {Hub.date(motion.report_due_on, @today)}</p>
      </article>
    </section>
    """
  end

  defp status_class(i, statuses, current) do
    j = Enum.find_index(statuses, fn {k, _} -> k == current end)

    cond do
      i < j -> "war"
      i == j -> "jetzt"
      true -> nil
    end
  end

  attr(:project, :map, required: true)

  defp value(assigns) do
    ~H"""
    <section class="hub-block" id="nutzen">
      <h2>
        Nutzen und Erfolg
        <button type="button" class="hub-aktion" phx-click="open" phx-value-dialog="value">Bearbeiten</button>
      </h2>
      <%= if @project.value && (@project.value.proposition || @project.value.success_metrics) do %>
        <p :if={@project.value.proposition} class="mt-1"><b>Was sich ändert:</b> {@project.value.proposition}</p>
        <p :if={@project.value.success_metrics} class="mt-1">
          <b>Woran wir es messen:</b> {@project.value.success_metrics}
        </p>
      <% else %>
        <p class="text-sm text-base-content/60 mt-1">Noch offen.</p>
      <% end %>
    </section>
    """
  end

  attr(:project, :map, required: true)
  attr(:today, Date, required: true)

  defp deadline(assigns) do
    assigns = assign(assigns, :deadline, Hub.deadline(assigns.project, assigns.today))

    ~H"""
    <span
      :if={@deadline}
      class={["badge badge-sm badge-soft", if(elem(@deadline, 0) == :overdue, do: "badge-error", else: "badge-warning")]}
    >
      {elem(@deadline, 1)}
    </span>
    """
  end

  ## Dialogs

  attr(:dialog, :any, required: true)
  attr(:form, :any, required: true)
  attr(:project, :map, required: true)
  attr(:motion, :any, default: nil)
  attr(:label, :string, default: nil)
  attr(:open_more, :boolean, default: false)

  defp dialogs(%{dialog: nil} = assigns), do: ~H""

  defp dialogs(%{dialog: {:event, _}} = assigns) do
    ~H"""
    <.dialog id="eintrag" title="Was ist passiert?" subtitle={@project.title} for={@form} submit="Eintragen">
      <.event_fields form={@form} phase={@project.phase} open={@open_more} />
    </.dialog>
    """
  end

  defp dialogs(%{dialog: {:motion_event, _}} = assigns) do
    ~H"""
    <.dialog
      id="antrag-eintrag"
      title={"#{Hub.name(:motion_kinds, @motion.kind)} aktualisieren"}
      subtitle={@motion.title}
      for={@form}
      submit="Aktualisieren"
    >
      <.event_fields form={@form} phase={@project.phase} motion open={@open_more} />
    </.dialog>
    """
  end

  defp dialogs(%{dialog: {:next_step, _}} = assigns) do
    ~H"""
    <.dialog id="schritt" title="Nächster Schritt" subtitle={@project.title} for={@form} submit="Sichern">
      <.step_fields text={@form[:text]} assignee={@form[:assignee]} due_on={@form[:due_on]} />
    </.dialog>
    """
  end

  defp dialogs(%{dialog: {:motion, _}} = assigns) do
    ~H"""
    <.dialog id="antrag-neu" title="Antrag beginnen" subtitle={@project.title} for={@form} submit="Beginnen">
      <.input field={@form[:title]} label="Titel" phx-mounted={JS.focus()} />
      <.input field={@form[:kind]} type="select" label="Art" options={options(Labels.motion_kinds())} />
      <.input field={@form[:motion_text]} type="textarea" label="Beschlussvorschlag" rows="3" />
      <.input field={@form[:addressee]} label="An wen?" />
      <.input field={@form[:document_ref]} label="Wo liegt der Text?" />
      <p class="text-xs text-base-content/60 -mt-1">Nur ein Verweis. Der Text selbst bleibt dort.</p>
    </.dialog>
    """
  end

  defp dialogs(%{dialog: {:fact, _}} = assigns) do
    ~H"""
    <.dialog id="fakt" title="Fakt ergänzen" subtitle={@project.title} for={@form} submit="Ergänzen">
      <.input field={@form[:statement]} type="textarea" label="Was steht fest?" rows="2" phx-mounted={JS.focus()} />
      <.input field={@form[:citation]} label="Woher wissen wir das?" />
      <p class="text-xs text-base-content/60 -mt-1 mb-2">
        Dokument mit Seite oder Paragraf, oder eine Auskunft mit Datum.
      </p>
      <.input field={@form[:url]} type="url" label="Link, falls vorhanden" />
      <.input field={@form[:fetched_on]} type="date" label="Abgerufen oder erhalten am" />
      <.input field={@form[:verified]} type="checkbox" label="Ich habe das selbst nachgeprüft" />
    </.dialog>
    """
  end

  defp dialogs(%{dialog: {:variant, _}} = assigns) do
    ~H"""
    <.dialog
      id="variante"
      title={"Variante #{Phoenix.HTML.Form.input_value(@form, :label)} ergänzen"}
      subtitle={@project.title}
      for={@form}
      submit="Ergänzen"
    >
      <.input field={@form[:title]} label="Worum geht es?" phx-mounted={JS.focus()} />
      <.input field={@form[:description]} type="textarea" label="Genauer, falls nötig" rows="2" />
      <.input name="variant[legal_basis]" id="variant_legal_basis" value={@form.params["legal_basis"]} label="Rechtsgrundlage" />
      <.input name="variant[prerequisite]" id="variant_prerequisite" value={@form.params["prerequisite"]} label="Was muss dafür erfüllt sein?" />
    </.dialog>
    """
  end

  defp dialogs(%{dialog: {:variant_decide, _}} = assigns) do
    ~H"""
    <.dialog
      id="variante-entscheiden"
      title={"Variante #{@label} #{if @form.params["status"] == "rejected", do: "verwerfen", else: "wählen"}"}
      subtitle={@project.title}
      for={@form}
      submit={if @form.params["status"] == "rejected", do: "Verwerfen", else: "Wählen"}
    >
      <input type="hidden" name="decision[status]" value={@form.params["status"]} />
      <.input field={@form[:by]} type="select" label="Wer hat entschieden?" options={options(Labels.actors())} />
      <.input
        field={@form[:reason]}
        label={if @form.params["status"] == "rejected", do: "Warum nicht?", else: "Warum diese?"}
        phx-mounted={JS.focus()}
      />
      <p class="text-xs text-base-content/60 -mt-1">Steht im Stand.</p>
    </.dialog>
    """
  end

  defp dialogs(%{dialog: {:cross_reference, _}} = assigns) do
    ~H"""
    <.dialog id="querverweis" title="Querverweis ergänzen" subtitle={@project.title} for={@form} submit="Ergänzen">
      <.input field={@form[:kind]} type="select" label="Wohin?" options={options(Labels.cross_reference_kinds())} />
      <.input field={@form[:target]} label="Adresse oder Name" phx-mounted={JS.focus()} />
      <p class="text-xs text-base-content/60 -mt-1">Bei einem komki-Raum nur seine Kennung. Querverweise stehen nie im Stand.</p>
    </.dialog>
    """
  end

  defp dialogs(%{dialog: {:value, _}} = assigns) do
    ~H"""
    <.dialog id="nutzen-form" title="Nutzen und Erfolg" subtitle={@project.title} for={@form} submit="Sichern">
      <.input field={@form[:proposition]} type="textarea" label="Was ändert sich, für wen?" rows="3" phx-mounted={JS.focus()} />
      <.input field={@form[:success_metrics]} type="textarea" label="Woran messen wir den Erfolg?" rows="3" />
    </.dialog>
    """
  end

  defp dialogs(%{dialog: {:dispose, _}} = assigns) do
    ~H"""
    <.dialog id="ablegen" title={"„#{@project.title}“ ablegen"} for={@form} submit="Ablegen">
      <.input
        field={@form[:disposition]}
        type="select"
        label="Wie?"
        options={[
          {"Ruht, kommt vielleicht wieder", "resting"},
          {"Abgeschlossen, Ziel erreicht oder Antrag erledigt", "completed"},
          {"Verworfen, auch wenn es in einem anderen Projekt aufgegangen ist", "rejected"}
        ]}
      />
      <.input field={@form[:by]} type="select" label="Wer hat entschieden?" options={options(Labels.actors())} />
      <.input field={@form[:reason]} label="Warum?" phx-mounted={JS.focus()} />
      <p class="text-xs text-base-content/60 -mt-1">Steht im Stand.</p>
    </.dialog>
    """
  end

  defp dialogs(%{dialog: {:resume, _}} = assigns) do
    ~H"""
    <.dialog id="wieder" title={"„#{@project.title}“ wieder aufnehmen"} for={@form} submit="Wieder aufnehmen">
      <.input field={@form[:by]} type="select" label="Wer hat entschieden?" options={options(Labels.actors())} />
      <.input field={@form[:reason]} label="Warum jetzt?" phx-mounted={JS.focus()} />
    </.dialog>
    """
  end
end
