defmodule RatsprojekteWeb.ProjektLive.Index do
  use RatsprojekteWeb, :live_view

  alias Ratsprojekte.{Repo, Schemas.Projekt}
  import Ecto.Query

  @impl true
  def mount(_params, _session, socket) do
    projekte =
      Repo.all(
        from p in Projekt,
          order_by: [desc: p.prioritaet, desc: p.inserted_at],
          preload: [:blocker]
      )

    {:ok, assign(socket, projekte: projekte)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto p-6">
      <h1 class="text-2xl font-bold mb-6">Stadtrats-Projekte</h1>

      <div class="space-y-4">
        <div :for={projekt <- @projekte} class="border rounded-lg p-4 hover:bg-gray-50">
          <.link navigate={"/projekte/#{projekt.id}"} class="block">
            <div class="flex items-center justify-between">
              <h2 class="text-lg font-semibold">{projekt.titel}</h2>
              <div class="flex gap-2">
                <.status_badge status={projekt.status} />
                <.prio_badge prio={projekt.prioritaet} />
              </div>
            </div>
            <p class="text-sm text-gray-600 mt-1">{projekt.beschreibung}</p>
            <p class="text-xs text-gray-400 mt-2">
              {length(projekt.blocker)} Blocker
            </p>
          </.link>
        </div>
      </div>
    </div>
    """
  end

  attr(:status, :atom, required: true)

  defp status_badge(assigns) do
    colors = %{
      idee: "bg-blue-100 text-blue-800",
      aktiv: "bg-green-100 text-green-800",
      blockiert: "bg-red-100 text-red-800",
      abgeschlossen: "bg-gray-100 text-gray-800"
    }

    assigns = assign(assigns, :color, Map.get(colors, assigns.status, "bg-gray-100"))

    ~H"""
    <span class={"px-2 py-1 rounded text-xs font-medium #{@color}"}>
      {@status}
    </span>
    """
  end

  attr(:prio, :atom, required: true)

  defp prio_badge(assigns) do
    colors = %{
      hoch: "bg-red-100 text-red-800",
      mittel: "bg-yellow-100 text-yellow-800",
      niedrig: "bg-gray-100 text-gray-800"
    }

    assigns = assign(assigns, :color, Map.get(colors, assigns.prio, "bg-gray-100"))

    ~H"""
    <span class={"px-2 py-1 rounded text-xs #{@color}"}>
      {@prio}
    </span>
    """
  end
end
