defmodule RatsprojekteWeb.ProjektLive.Show do
  use RatsprojekteWeb, :live_view

  alias Ratsprojekte.Repo
  alias Ratsprojekte.Schemas.Projekt

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    projekt = Repo.get!(Projekt, id)
    projekt = Repo.preload(projekt, blocker: [:quellen, :depends_on, :blocks], quellen: [])

    {:ok, assign(socket, projekt: projekt)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto p-6">
      <.link navigate="/" class="text-sm text-blue-600 hover:underline mb-4 inline-block">
        ← Zurück zur Übersicht
      </.link>

      <div class="flex items-center justify-between mb-4">
        <h1 class="text-2xl font-bold">{@projekt.titel}</h1>
        <div class="flex gap-2">
          <span class="px-2 py-1 rounded text-xs font-medium bg-blue-100 text-blue-800">
            {@projekt.status}
          </span>
          <span class="px-2 py-1 rounded text-xs bg-red-100 text-red-800">
            {@projekt.prioritaet}
          </span>
        </div>
      </div>

      <p class="text-gray-700 mb-6">{@projekt.beschreibung}</p>

      <h2 class="text-lg font-semibold mb-3">Blocker ({length(@projekt.blocker)})</h2>

      <div class="space-y-3">
        <div
          :for={blocker <- @projekt.blocker}
          class="border-l-4 pl-4 py-2"
          style={"border-color: #{typ_color(blocker.typ)}"}
        >
          <div class="flex items-center justify-between">
            <h3 class="font-medium">{blocker.titel}</h3>
            <div class="flex gap-2">
              <span class="text-xs px-2 py-0.5 rounded bg-gray-100">{blocker.typ}</span>
              <span class="text-xs px-2 py-0.5 rounded {status_color(blocker.status)}">
                {blocker.status}
              </span>
            </div>
          </div>

          <p class="text-sm text-gray-600 mt-1">{blocker.beschreibung}</p>

          <div :if={blocker.depends_on != []} class="mt-2">
            <span class="text-xs text-gray-500">Hängt ab von:</span>
            <ul class="text-xs text-gray-600 ml-4 mt-1">
              <li :for={dep <- blocker.depends_on}>
                ↳ {dep.titel} <span class="text-gray-400">({dep.status})</span>
              </li>
            </ul>
          </div>

          <div :if={blocker.quellen != []} class="mt-2">
            <span class="text-xs text-gray-500">Quellen:</span>
            <ul class="text-xs text-blue-600 ml-4 mt-1">
              <li :for={q <- blocker.quellen}>
                <a :if={q.url} href={q.url} target="_blank">{q.titel}</a>
                <span :if={!q.url}>{q.titel}</span>
                <span :if={q.paragraf} class="text-gray-500"> —   {q.paragraf}</span>
              </li>
            </ul>
          </div>
        </div>
      </div>

      <div :if={@projekt.quellen != []} class="mt-6">
        <h2 class="text-lg font-semibold mb-3">Projekt-Quellen</h2>
        <ul class="text-sm text-blue-600">
          <li :for={q <- @projekt.quellen}>
            <a :if={q.url} href={q.url} target="_blank">{q.titel}</a>
            <span :if={!q.url}>{q.titel}</span>
          </li>
        </ul>
      </div>
    </div>
    """
  end

  defp typ_color(:rechtlich), do: "#dc2626"
  defp typ_color(:finanziell), do: "#ca8a04"
  defp typ_color(:politisch), do: "#7c3aed"
  defp typ_color(:organisatorisch), do: "#0891b2"
  defp typ_color(:infrastruktur), do: "#ea580c"
  defp typ_color(_), do: "#6b7280"

  defp status_color(:offen), do: "bg-red-100 text-red-800"
  defp status_color(:in_arbeit), do: "bg-yellow-100 text-yellow-800"
  defp status_color(:geloest), do: "bg-green-100 text-green-800"
end
