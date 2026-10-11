defmodule RatsprojekteWeb.NavAssigns do
  @moduledoc """
  Stellt die für das Root-Layout nötigen Navigations-Assigns in einer
  LiveView bereit.

  Das Root-Layout (`root.html.heex`) rendert die globale Navbar und greift
  dabei auf `@nav_section` und `@pending_count` zu. Während der initiale
  Page-Render über den `RatsprojekteWeb.Plugs.Nav`-Plug gespeist wird, müssen
  LiveViews die Assigns für spätere Re-Renders (Live-Navigation, Morph) selbst
  setzen, da der Plug-Stack beim LiveView-Update nicht mehr läuft.

  Aufruf in jeder LiveView-`mount/3`:

      NavAssigns.attach(socket, :projekte)
  """

  alias Ratsprojekte.Repo
  alias Ratsprojekte.Schemas.PendingProposal
  import Ecto.Query
  import Phoenix.Component, only: [assign: 2]

  @spec attach(Phoenix.LiveView.Socket.t(), atom() | nil) :: Phoenix.LiveView.Socket.t()
  def attach(socket, section) do
    pending_count =
      Repo.aggregate(
        from(pp in PendingProposal, where: pp.status == :pending),
        :count
      )

    assign(socket, nav_section: section, pending_count: pending_count)
  end
end
