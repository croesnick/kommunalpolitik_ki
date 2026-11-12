defmodule RatsprojekteWeb.OverviewLive do
  @moduledoc """
  The overview: all active projects as cards in columns by phase, filed
  ones below. Each card opens the main flow „Was ist passiert?“ in place,
  so six projects after a session are six dialogs, not eighteen. „Neue
  Idee“ starts a project (`/?neu`).
  """

  use RatsprojekteWeb, :live_view

  import RatsprojekteWeb.HubComponents

  alias Ratsprojekte.{Labels, Projects}
  alias Ratsprojekte.Projects.Project
  alias RatsprojekteWeb.{Hub, MainFlow}

  @filters [{"alle", "Alle"}, {"du", "Du bist dran"}, {"achtung", "Braucht Aufmerksamkeit"}]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "Übersicht", filter: "alle", dialog: nil, form: nil)
     |> load()}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    if Map.has_key?(params, "neu"),
      do: {:noreply, open_new(socket)},
      else: {:noreply, socket}
  end

  defp load(socket) do
    assign(socket, projects: Projects.list_projects(), today: Projects.today())
  end

  defp open_new(socket) do
    params = %{"title" => "", "short" => "", "origin" => "", "slug" => ""}

    assign(socket,
      dialog: {:new, ""},
      form: to_form(Projects.change_project(%Project{}, %{}), as: :project),
      params: params
    )
  end

  @impl true
  def handle_event("filter", %{"filter" => filter}, socket)
      when filter in ["alle", "du", "achtung"],
      do: {:noreply, assign(socket, filter: filter)}

  def handle_event("eintragen", %{"slug" => slug}, socket) do
    project = Projects.get_project!(slug)
    params = MainFlow.initial(project)

    {:noreply,
     assign(socket, dialog: {:event, project}, params: params, form: MainFlow.form(params))}
  end

  def handle_event("close", _params, socket), do: {:noreply, close(socket)}

  def handle_event("validate", %{"event" => params}, socket) do
    params = MainFlow.validate(params, socket.assigns.params)
    {:noreply, assign(socket, params: params, form: MainFlow.form(params, :validate))}
  end

  # The short name follows the title until someone types one of their own.
  def handle_event("validate", %{"project" => params}, socket) do
    {:new, suggested} = socket.assigns.dialog
    follows = params["slug"] in ["", suggested]
    suggestion = Projects.suggest_slug(params["title"])
    params = if follows, do: Map.put(params, "slug", suggestion), else: params
    suggested = if follows, do: suggestion, else: suggested

    {:noreply,
     assign(socket,
       dialog: {:new, suggested},
       params: params,
       form:
         %Project{}
         |> Projects.change_project(params)
         |> Map.put(:action, :validate)
         |> to_form(as: :project)
     )}
  end

  def handle_event("save", %{"event" => params}, socket) do
    {:event, project} = socket.assigns.dialog

    case MainFlow.save(project, nil, params) do
      {:ok, project} ->
        {:noreply,
         socket |> close() |> load() |> put_flash(:info, "Eingetragen: #{project.title}")}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(%{changeset | action: :insert}, as: :event))}
    end
  end

  def handle_event("save", %{"project" => params}, socket) do
    case Projects.create_project(params) do
      {:ok, project} ->
        {:noreply,
         socket
         |> put_flash(:info, "Idee angelegt")
         |> push_navigate(to: ~p"/projekte/#{project.slug}")}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(%{changeset | action: :insert}, as: :project))}
    end
  end

  # A closed „Neue Idee“ leaves `/?neu`, so a reload does not reopen it.
  defp close(%{assigns: %{dialog: {:new, _}}} = socket),
    do: socket |> assign(dialog: nil, form: nil) |> push_patch(to: ~p"/")

  defp close(socket), do: assign(socket, dialog: nil, form: nil)

  @impl true
  def render(assigns) do
    active = Enum.reject(assigns.projects, & &1.disposition)

    columns =
      for {phase, name} <- Labels.phases() do
        {phase, name,
         Enum.filter(active, &(&1.phase == phase and shown?(&1, assigns.filter, assigns.today)))}
      end

    assigns =
      assign(assigns,
        columns: columns,
        filed: Enum.filter(assigns.projects, & &1.disposition),
        filters: @filters
      )

    ~H"""
    <.hub flash={@flash} today={@today}>
      <div class="flex flex-wrap items-center gap-2" id="filter" role="group" aria-label="Filter">
        <button
          :for={{key, name} <- @filters}
          type="button"
          phx-click="filter"
          phx-value-filter={key}
          aria-pressed={to_string(@filter == key)}
          class={["btn btn-sm", if(@filter == key, do: "btn-neutral", else: "btn-ghost")]}
        >
          {name}
        </button>
        <span class="text-xs text-base-content/60 sm:ml-auto">
          Wer gehört wurde: F Fraktion, V Vorstand, B Basis, E Externe. Ausgefüllt heißt ja.
        </span>
      </div>

      <p :if={@projects == []} class="hub-leer" id="leer">
        Noch keine Projekte. Leg mit „Neue Idee“ das erste an.
      </p>

      <div :if={@projects != []} class="hub-brett" id="brett">
        <section :for={{phase, name, cards} <- @columns} class="hub-spalte" id={"spalte-#{phase}"}>
          <h2 class="font-bold text-sm">
            {name}<span class="font-normal text-base-content/60 ml-1">{length(cards)}</span>
          </h2>
          <p class="text-xs text-base-content/60 mb-1">{Hub.phase_question(phase)}</p>
          <.card :for={project <- cards} project={project} today={@today} />
        </section>
      </div>

      <p :if={@filed != []} class="text-sm text-base-content/70 mt-4" id="abgelegt">
        Abgelegt:
        <span :for={{project, i} <- Enum.with_index(@filed)}>
          <.link navigate={~p"/projekte/#{project.slug}"} class="link link-primary">
            {project.title}
          </.link>
          ({Hub.name(:dispositions, project.disposition)}){if i < length(@filed) - 1, do: ","}
        </span>
      </p>

      <.dialog
        :if={match?({:event, _}, @dialog)}
        id="eintrag"
        title="Was ist passiert?"
        subtitle={elem(@dialog, 1).title}
        for={@form}
        submit="Eintragen"
      >
        <.event_fields form={@form} phase={elem(@dialog, 1).phase} />
      </.dialog>

      <.dialog
        :if={match?({:new, _}, @dialog)}
        id="neue-idee-form"
        title="Neue Idee"
        for={@form}
        submit="Idee anlegen"
      >
        <.input field={@form[:title]} label="Titel" maxlength="140" phx-mounted={JS.focus()} />
        <.input field={@form[:short]} label="Ein Satz, worum es geht" />
        <.input field={@form[:origin]} label="Woher kommt das?" />
        <p class="text-xs text-base-content/60 -mt-1 mb-2">Ein Anlass, kein Name. Namen gehören in den Vault.</p>
        <.input field={@form[:slug]} label="Kurzname" />
        <p class="text-xs text-base-content/60 -mt-1">
          Entsteht aus dem Titel. Damit findest du das Projekt auch im Vault. Er bleibt fest, auch wenn sich der Titel ändert.
        </p>
      </.dialog>
    </.hub>
    """
  end

  defp shown?(_project, "alle", _today), do: true
  defp shown?(project, "du", _today), do: Hub.mine?(project)
  defp shown?(project, "achtung", today), do: Hub.attention?(project, today)

  attr(:project, :map, required: true)
  attr(:today, Date, required: true)

  defp card(assigns) do
    ~H"""
    <article class="hub-karte" id={"karte-#{@project.slug}"}>
      <.link navigate={~p"/projekte/#{@project.slug}"} class="font-semibold leading-snug hover:underline">
        {@project.title}
      </.link>
      <p :if={@project.next_step} class="text-sm text-base-content/80 mt-1">
        {@project.next_step.text}{if @project.next_step.assignee,
          do: " · #{Hub.assignee(@project.next_step.assignee)}"}{if @project.next_step.due_on,
          do: " · bis #{Hub.date(@project.next_step.due_on, @today)}"}
      </p>
      <p :if={!@project.next_step} class="text-sm text-base-content/50 mt-1">
        Noch kein nächster Schritt
      </p>
      <div class="flex flex-wrap items-center gap-1 mt-2">
        <span
          :for={{_circle, name, heard} <- Hub.heard(@project)}
          class={["hub-kreis", heard && "hub-kreis-ja"]}
          title={"#{name} #{if heard, do: "gehört", else: "noch nicht gehört"}"}
        >
          {String.first(name)}
        </span>
        <.marker project={@project} today={@today} />
        <button
          type="button"
          class="btn btn-ghost btn-xs ml-auto text-primary"
          phx-click="eintragen"
          phx-value-slug={@project.slug}
          id={"eintragen-#{@project.slug}"}
          aria-label={"Eintragen: #{@project.title}"}
        >
          Eintragen
        </button>
      </div>
    </article>
    """
  end

  attr(:project, :map, required: true)
  attr(:today, Date, required: true)

  defp marker(assigns) do
    assigns =
      assign(assigns,
        deadline: Hub.deadline(assigns.project, assigns.today),
        lying: Hub.lying_weeks(assigns.project, assigns.today)
      )

    ~H"""
    <span :if={@deadline} class={["badge badge-sm badge-soft", if(elem(@deadline, 0) == :overdue, do: "badge-error", else: "badge-warning")]}>
      {elem(@deadline, 1)}
    </span>
    <span :if={!@deadline && @lying} class="badge badge-sm badge-soft badge-warning">
      Liegt seit {@lying} Wochen
    </span>
    """
  end
end
