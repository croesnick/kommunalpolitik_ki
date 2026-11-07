defmodule RatsprojekteWeb.Router do
  use RatsprojekteWeb, :router

  # All assets are served from priv/static, so everything is limited to the own origin.
  # `connect-src 'self'` covers the LiveView WebSocket (`/live`) in current browsers.
  # Exception: `style-src 'unsafe-inline'`, because several LiveViews set inline `style`
  # attributes that LiveView re-applies via setAttribute on every DOM patch.
  @content_security_policy Enum.join(
                             [
                               "default-src 'self'",
                               "script-src 'self'",
                               "style-src 'self' 'unsafe-inline'",
                               "img-src 'self' data:",
                               "connect-src 'self'",
                               "base-uri 'self'",
                               "form-action 'self'",
                               "frame-ancestors 'self'"
                             ],
                             "; "
                           )

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_live_flash)
    plug(:put_root_layout, html: {RatsprojekteWeb.Layouts, :root})
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers, %{"content-security-policy" => @content_security_policy})
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
