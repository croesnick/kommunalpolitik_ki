defmodule RatsprojekteWeb.BriefingComponents do
  @moduledoc """
  The briefing on paper (A4): the document Fraktion and Vorstand get.
  The same component renders the preview, the review and the document
  that is stored when the briefing is issued, so what the editor sees
  is what goes out.
  """

  use RatsprojekteWeb, :html

  import RatsprojekteWeb.HubComponents, only: [tally: 1]

  alias Phoenix.HTML.Safe
  alias Ratsprojekte.Briefings
  alias RatsprojekteWeb.Hub

  @doc """
  The paper. `mode` is `:preview`, `:issued` or `:review`; `at` is the
  local time of the issue (`:issued`) or nil; `today` dates the others.
  """
  attr(:briefing, :map, required: true)
  attr(:mode, :atom, required: true, values: [:preview, :issued, :review])
  attr(:at, NaiveDateTime, default: nil)
  attr(:today, Date, required: true)

  def paper(assigns) do
    day = if assigns.at, do: NaiveDateTime.to_date(assigns.at), else: assigns.today

    assigns =
      assign(assigns,
        day: day,
        dated:
          long_date(day) <>
            if(assigns.at, do: ", #{Calendar.strftime(assigns.at, "%H:%M")} Uhr", else: "")
      )

    ~H"""
    <article class="hub-papier" id="papier">
      <p class="hub-papier-kopf">
        {if @mode == :review, do: "Rückblick · nicht ausgegeben", else: "Für Fraktion und Vorstand"}
      </p>
      <h1 class="hub-titel">Stand der Ratsprojekte, {@dated}</h1>

      <div class="hub-ueberblick" id="ueberblick">
        <div :for={{name, count} <- @briefing.phases}><b>{count}</b>{name}</div>
      </div>

      <section :if={@briefing.due != []} id="wer-ist-dran">
        <h2>Wer ist dran</h2>
        <table class="hub-dran">
          <tbody :for={{who, steps} <- @briefing.due}>
            <tr><th colspan="3">{who}</th></tr>
            <tr :for={step <- steps}>
              <td>{step.title}</td>
              <td>{step.text}</td>
              <td>{if step.due_on, do: "bis #{Hub.date(step.due_on, @day)}"}</td>
            </tr>
          </tbody>
        </table>
      </section>

      <section :if={@briefing.since} id="neu-seit">
        <h2>{since_heading(@briefing.since)}</h2>
        <dl :if={@briefing.news != []} class="hub-sgrid">
          <%= for {title, entries} <- @briefing.news do %>
            <dt>{title}</dt>
            <dd>
              <div :for={entry <- entries}>
                {entry.text}<span :if={entry.by} class="hub-papier-leise"> ({entry.by})</span>
              </div>
            </dd>
          <% end %>
        </dl>
        <p :if={@briefing.news == []} class="hub-papier-zeile">Nichts.</p>
      </section>

      <section :for={survey <- @briefing.surveys} class="hub-papier-befragung">
        <h2>Meinungsbild ({survey.circle}): {survey.title}</h2>
        <p class="hub-papier-leise hub-papier-zeile">
          {survey.question} Rücklauf vom {Hub.date(survey.as_of, @day)}. Nicht bindend.
        </p>
        <table class="hub-ergebnis">
          <tbody>
            <tr :for={row <- survey.rows}>
              <td><b>{row.title}</b></td>
              <td class="hub-ergebnis-vert"><.tally :if={row.tally} tally={row.tally} /></td>
              <td>
                {row.statement}
                <ul :if={row.arguments != []} class="hub-argumente">
                  <li :for={argument <- row.arguments}>
                    {if argument["stance"] == "for", do: "Dafür: ", else: "Dagegen: "}{argument["text"]}
                  </li>
                </ul>
              </td>
            </tr>
          </tbody>
        </table>
      </section>

      <section :for={{phase, projects} <- @briefing.groups} class="hub-papier-phase">
        <h2>{phase}</h2>
        <div :for={project <- projects} class="hub-papier-projekt">
          <b>{project.title}</b>
          <p :if={project.short} class="hub-papier-leise">{project.short}</p>
          <dl class="hub-sgrid">
            <%= if project.survey do %>
              <dt>Befragung</dt>
              <dd>Läuft: „{project.survey}“</dd>
            <% end %>
            <%= for opinion <- project.opinions do %>
              <dt>{opinion.circle}<small>{Hub.date(opinion.on, @day)}</small></dt>
              <dd>
                {opinion.statement || (opinion.tally && "#{Enum.sum(opinion.tally)} Personen")}
                <.tally :if={opinion.tally && !opinion.tally_above} tally={opinion.tally} />
              </dd>
            <% end %>
            <%= if project.not_heard != [] do %>
              <dt>Noch nicht gehört</dt>
              <dd class="hub-papier-leise">{Enum.join(project.not_heard, ", ")}</dd>
            <% end %>
            <%= if project.decision do %>
              <dt>Zuletzt entschieden<small>{Hub.date(project.decision.on, @day)}</small></dt>
              <dd>
                {project.decision.text}<span :if={project.decision.by} class="hub-papier-leise"> ({project.decision.by})</span>
              </dd>
            <% end %>
            <%= if project.chosen do %>
              <dt>Variante</dt>
              <dd>{project.chosen}</dd>
            <% end %>
            <%= for fact <- project.facts do %>
              <dt>Fakt</dt>
              <dd>
                {fact.statement}
                <span class="hub-papier-leise">({fact.citation}{if !fact.verified, do: ", nicht verifiziert"})</span>
              </dd>
            <% end %>
            <%= for motion <- project.motions do %>
              <dt>{motion.kind}</dt>
              <dd>
                „{motion.title}“: {motion.state}{if motion.report_due_on,
                  do: ", Bericht bis #{Hub.date(motion.report_due_on, @day)}"}
              </dd>
            <% end %>
            <%= for note <- project.notes do %>
              <dt>Notiz</dt>
              <dd>{note}</dd>
            <% end %>
          </dl>
        </div>
      </section>

      <section :if={@briefing.filed != []} id="abgelegt">
        <h2>Abgelegt</h2>
        <p class="hub-papier-zeile">
          {Enum.map_join(@briefing.filed, ", ", fn {title, disposition} -> "#{title} (#{disposition})" end)}
        </p>
      </section>

      <p class="hub-papier-fuss">
        {footer(@mode, @dated, @briefing.editor)}
      </p>
    </article>
    """
  end

  @doc "The paper as one HTML string: what is stored when the briefing is issued."
  @spec to_html(map(), NaiveDateTime.t(), Date.t()) :: String.t()
  def to_html(briefing, at, today) do
    %{__changed__: nil, briefing: briefing, mode: :issued, at: at, today: today}
    |> paper()
    |> Safe.to_iodata()
    |> IO.iodata_to_binary()
  end

  @doc "`12.11.2026`"
  @spec long_date(Date.t()) :: String.t()
  def long_date(date), do: Calendar.strftime(date, "%d.%m.%Y")

  defp since_heading({:issued, at}) do
    local = Briefings.local(at)

    "Neu seit #{long_date(NaiveDateTime.to_date(local))}, #{Calendar.strftime(local, "%H:%M")} Uhr"
  end

  defp since_heading({:day, day}), do: "Seit #{long_date(day)}"

  defp footer(:review, dated, editor),
    do: "Rückblick vom #{dated}, nicht ausgegeben. Gepflegt von #{editor}."

  defp footer(_mode, dated, editor),
    do:
      "Stand vom #{dated}, gepflegt von #{editor}. Nur für Fraktion und Vorstand. Enthält nichts Nichtöffentliches."
end
