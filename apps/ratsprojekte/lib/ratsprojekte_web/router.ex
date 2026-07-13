defmodule RatsprojekteWeb.Router do
  use RatsprojekteWeb, :router

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_live_flash)
    plug(:put_root_layout, html: {RatsprojekteWeb.Layouts, :root})
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
  end

  pipeline :api do
    plug(:accepts, ["json"])
  end

  # MCP-Endpoint für AI-Zugriff (dev-only, read-only)
  if Mix.env() == :dev do
    scope "/mcp" do
      pipe_through(:api)

      forward("/", Anubis.Server.Transport.StreamableHTTP.Plug, server: Ratsprojekte.MCP.Server)
    end
  end

  scope "/", RatsprojekteWeb do
    pipe_through(:browser)

    live("/", ProjektLive.Index, :index)
    live("/projekte/:id", ProjektLive.Show, :show)
  end
end
