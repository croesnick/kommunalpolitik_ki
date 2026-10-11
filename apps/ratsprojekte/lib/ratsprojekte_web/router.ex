defmodule RatsprojekteWeb.Router do
  use RatsprojekteWeb, :router

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_live_flash)
    plug(:put_root_layout, html: {RatsprojekteWeb.Layouts, :root})
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
    plug(RatsprojekteWeb.Plugs.Nav)
  end

  pipeline :api do
    plug(:accepts, ["json"])
  end

  pipeline :mcp do
    plug(:accepts, ["json", "event-stream"])
  end

  # MCP-Endpoint für AI-Zugriff (dev-only, read-only)
  if Mix.env() == :dev do
    scope "/mcp" do
      pipe_through(:mcp)

      forward("/", Anubis.Server.Transport.StreamableHTTP.Plug, server: Ratsprojekte.MCP.Server)
    end
  end

  scope "/", RatsprojekteWeb do
    pipe_through(:browser)

    live("/", ProjektLive.Index, :index)
    live("/projekte/:slug", ProjektLive.Show, :show)

    # Propose-Confirm-Pattern: GO-Gate für AI-Vorschläge in der LiveView
    live("/projekte/:projekt_slug/proposals", ProposalLive.Index, :index)
    live("/projekte/:projekt_slug/proposals/:id", ProposalLive.Show, :show)

    # Top-level proposals (für add_projekt Vorschläge ohne Eltern-Projekt)
    live("/proposals", ProposalLive.Index, :index)
    live("/proposals/:id", ProposalLive.Show, :show)
  end
end
