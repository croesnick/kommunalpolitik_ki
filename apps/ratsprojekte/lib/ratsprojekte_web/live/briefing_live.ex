defmodule RatsprojekteWeb.BriefingLive do
  @moduledoc """
  The briefing („Stand“): on the left exactly the paper Fraktion and
  Vorstand get, on the right what stays here and „Stand ausgeben“.

  - `/stand`: the preview; looking stores nothing.
  - `/stand?ab=2026-03-01`: the review from a chosen day, same version,
    never stored, resets nothing.
  - `/stand/:id`: an issued briefing, exactly as it went out.

  The hub makes no PDF: „Drucken“ opens the browser's print dialog, and
  the editor puts the file into the folder by hand (ADR 0004).
  """

  use RatsprojekteWeb, :live_view

  import RatsprojekteWeb.HubComponents
  import RatsprojekteWeb.BriefingComponents

  alias Ratsprojekte.{Briefings, Projects, Settings}
  alias RatsprojekteWeb.BriefingComponents

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "Stand", today: Projects.today())
     |> load_settings()}
  end

  @impl true
  def handle_params(%{"id" => id}, _uri, socket) do
    case Integer.parse(id) do
      {id, ""} -> show_issued(socket, Briefings.get_issued(id))
      _ -> show_issued(socket, nil)
    end
  end

  def handle_params(%{"ab" => day}, _uri, socket) do
    case Date.from_iso8601(day) do
      {:ok, day} -> {:noreply, socket |> assign(mode: :review, day: day) |> load()}
      {:error, _} -> {:noreply, push_patch(socket, to: ~p"/stand")}
    end
  end

  def handle_params(_params, _uri, socket),
    do: {:noreply, socket |> assign(mode: :preview, day: nil) |> load()}

  defp show_issued(socket, nil) do
    {:noreply,
     socket |> put_flash(:error, "Diesen Stand gibt es nicht.") |> push_navigate(to: ~p"/stand")}
  end

  defp show_issued(socket, issued) do
    {:noreply, socket |> assign(mode: :issued, issued: issued) |> load_issued()}
  end

  defp load(%{assigns: %{mode: :review, day: day}} = socket),
    do: socket |> assign(briefing: Briefings.review(day)) |> load_issued()

  defp load(socket) do
    socket
    |> assign(briefing: Briefings.preview(), last: Briefings.last_issued_at())
    |> load_issued()
  end

  defp load_issued(socket), do: assign(socket, issued_list: Briefings.list_issued())

  defp load_settings(socket) do
    name = Settings.editor_name()
    assign(socket, name_form: to_form(%{"name" => name || ""}, as: :redaktion))
  end

  @impl true
  def handle_event("ausgeben", _params, socket) do
    now = DateTime.truncate(DateTime.utc_now(), :second)
    briefing = Briefings.preview()
    html = BriefingComponents.to_html(briefing, Briefings.local(now), socket.assigns.today)
    {:ok, issued} = Briefings.issue(html, now)

    {:noreply,
     socket
     |> put_flash(
       :info,
       "Stand ausgegeben und gespeichert. Jetzt drucken und in den Ordner legen."
     )
     |> push_patch(to: ~p"/stand/#{issued.id}")}
  end

  def handle_event("rueckblick", %{"ab" => ""}, socket),
    do: {:noreply, push_patch(socket, to: ~p"/stand")}

  def handle_event("rueckblick", %{"ab" => day}, socket),
    do: {:noreply, push_patch(socket, to: ~p"/stand?#{[ab: day]}")}

  def handle_event("name", %{"redaktion" => params}, socket) do
    case Settings.set_editor_name(params) do
      {:ok, _name} ->
        {:noreply, socket |> load_settings() |> load() |> put_flash(:info, "Name gespeichert")}

      {:error, changeset} ->
        {:noreply,
         assign(socket, name_form: to_form(%{changeset | action: :update}, as: :redaktion))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.hub flash={@flash} today={@today} current={:briefing}>
      <div class="hub-buehne">
        <%= if @mode == :issued do %>
          <div class="hub-papier-gespeichert" id="ausgegeben">{Phoenix.HTML.raw(@issued.html)}</div>
        <% else %>
          <.paper briefing={@briefing} mode={@mode} today={@today} />
        <% end %>

        <aside class="hub-panel" id="panel">
          <%= case @mode do %>
            <% :preview -> %>
              <.preview_panel briefing={@briefing} last={@last} today={@today} name_form={@name_form} />
            <% :review -> %>
              <h2 class="font-bold">Rückblick</h2>
              <p class="mt-1">
                Alles seit dem gewählten Tag, in derselben Fassung wie der Stand. Gedacht als Vorbereitung für einen Bericht an Vorstand oder Fraktion. Der Rückblick wird nicht gespeichert und setzt nichts zurück.
              </p>
              <.review_field day={@day} />
              <.print_button />
              <.link patch={~p"/stand"} class="btn btn-ghost btn-sm w-full mt-2" id="zur-vorschau">Zur Vorschau</.link>
            <% :issued -> %>
              <h2 class="font-bold">Ausgegeben am {issued_at(@issued.issued_at)}</h2>
              <p class="mt-1">So ist dieser Stand hinausgegangen. Er ändert sich nicht mehr.</p>
              <.print_button />
              <p class="text-xs text-base-content/60 mt-1">
                Die Datei legst du selbst in den Ordner für den Stand in der Nextcloud.
              </p>
              <.link patch={~p"/stand"} class="btn btn-ghost btn-sm w-full mt-2" id="zur-vorschau">Zur Vorschau</.link>
          <% end %>
          <.issued_list list={@issued_list} />
        </aside>
      </div>
    </.hub>
    """
  end

  attr(:briefing, :map, required: true)
  attr(:last, DateTime, default: nil)
  attr(:today, Date, required: true)
  attr(:name_form, Phoenix.HTML.Form, required: true)

  defp preview_panel(assigns) do
    overdue =
      for {_who, steps} <- assigns.briefing.due,
          step <- steps,
          step.due_on && Date.before?(step.due_on, assigns.today),
          do: step

    assigns = assign(assigns, overdue: length(overdue), withheld: assigns.briefing.withheld)

    ~H"""
    <h2 class="font-bold">So verlässt es den Rechner</h2>
    <p class="mt-1">
      Links steht genau das, was Fraktion und Vorstand bekommen. Durch das Ansehen wird nichts gespeichert.
    </p>
    <p class="mt-3 font-semibold">Bleibt hier:</p>
    <ul class="list-disc pl-5" id="bleibt-hier">
      <li>{count(@withheld.notes, "Notiz", "Notizen")} nur für dich</li>
      <li>{count(@withheld.cross_references, "Querverweis", "Querverweise")}</li>
      <li>Herkunft von {count(@withheld.origins, "Projekt", "Projekten")}</li>
    </ul>
    <div class="hub-hinweis">
      Lies „Wer ist dran“ und die Gründe kurz durch. Dort schreibst du am ehesten etwas, das nicht für alle gedacht ist. Nichtöffentliches gehört nie hierher.
    </div>
    <div :if={@overdue > 0} class="hub-hinweis" id="abgelaufen">
      {if @overdue == 1,
        do: "Eine Frist in „Wer ist dran“ ist abgelaufen.",
        else: "#{@overdue} Fristen in „Wer ist dran“ sind abgelaufen."} Im Stand steht nur das Datum, gelesen wird es trotzdem als überfällig. Frag nach oder pass die Frist an, bevor du ausgibst.
    </div>
    <button
      type="button"
      class="btn btn-primary w-full mt-3"
      id="ausgeben"
      phx-click="ausgeben"
      phx-disable-with="Speichert …"
    >
      Stand ausgeben
    </button>
    <p class="text-xs text-base-content/60 mt-1">
      Der Hub merkt sich das Dokument mit Uhrzeit. Ab dann zählt „Neu seit“ von diesem Zeitpunkt an.{if @last,
        do: " Letzte Ausgabe: #{issued_at(@last)}."}
    </p>
    <p class="text-xs text-base-content/60 mt-2">
      Stimmt etwas in einem ausgegebenen Stand nicht, schreib einen Eintrag „Korrektur: …“. Er steht im nächsten Stand unter „Neu seit“. Ist es heikel, gib gleich einen neuen Stand aus.
    </p>

    <.form for={@name_form} id="redaktion-form" phx-submit="name" class="mt-4">
      <.input field={@name_form[:name]} label="Wer führt den Hub?" placeholder="Redaktion" maxlength="80" />
      <p class="text-xs text-base-content/60 -mt-1">
        Steht im Stand bei „Wer ist dran“ und unten auf dem Blatt. Ohne Namen steht dort „Redaktion“.
      </p>
      <button type="submit" class="btn btn-sm mt-1" id="name-speichern">Name speichern</button>
    </.form>

    <.review_field />
    """
  end

  attr(:day, Date, default: nil)

  defp review_field(assigns) do
    ~H"""
    <form id="rueckblick-form" phx-change="rueckblick" phx-submit="rueckblick" class="mt-4">
      <label class="text-sm" for="rueckblick-ab">Rückblick ab</label>
      <input
        type="date"
        id="rueckblick-ab"
        name="ab"
        value={@day && Date.to_iso8601(@day)}
        class="input input-sm w-full mt-1"
      />
    </form>
    """
  end

  defp print_button(assigns) do
    ~H"""
    <button
      type="button"
      class="btn w-full mt-3"
      id="drucken"
      phx-click={JS.dispatch("hub:print")}
    >
      Drucken oder als PDF sichern
    </button>
    """
  end

  attr(:list, :list, required: true)

  defp issued_list(assigns) do
    ~H"""
    <div :if={@list != []} class="mt-4" id="bisher-ausgegeben">
      <p class="font-semibold">Bisher ausgegeben:</p>
      <ul>
        <li :for={issued <- @list}>
          <.link patch={~p"/stand/#{issued.id}"} class="link link-primary">
            {issued_at(issued.issued_at)}
          </.link>
        </li>
      </ul>
    </div>
    """
  end

  defp issued_at(at) do
    local = Briefings.local(at)
    "#{long_date(NaiveDateTime.to_date(local))}, #{Calendar.strftime(local, "%H:%M")} Uhr"
  end

  defp count(1, one, _many), do: "1 #{one}"
  defp count(n, _one, many), do: "#{n} #{many}"
end
