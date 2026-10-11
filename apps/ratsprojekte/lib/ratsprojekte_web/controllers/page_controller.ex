defmodule RatsprojekteWeb.PageController do
  use RatsprojekteWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
