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

  scope "/", RatsprojekteWeb do
    pipe_through(:browser)

    live("/", ProjektLive.Index, :index)
  end
end
