defmodule RatsprojekteWeb.Router do
  use RatsprojekteWeb, :router

  # CSP zurückgetragen aus dem alten Bestand (#435, ursprünglich #150/#151):
  # Alle Assets kommen aus priv/static, also bleibt alles auf der eigenen
  # Origin; `connect-src 'self'` deckt die LiveView-WebSocket (/live) ab.
  # Drei bewusste Ausnahmen, alle aus dem alten Bestand übernommen bzw.
  # für das Gerüst nötig:
  # - `style-src 'unsafe-inline'`: LiveViews setzen inline style-Attribute,
  #   die LiveView bei jedem DOM-Patch neu anwendet.
  # - Der SHA-256-Hash erlaubt allein das Inline-Theme-Script im Root-Layout
  #   (FOUC-Vermeidung, vor dem CSS). Ändert sich das Script, muss der Hash
  #   hier und im CSP-Test mitgezogen werden — der Test erzwingt das.
  # - `img-src 'self' data:`: aus dem alten Bestand übernommen; die eigene
  #   Oberfläche nutzt heute keine data:-Bilder, gestrichen wird es, wenn
  #   #437 die Hub-Oberfläche baut und nichts darauf angewiesen ist.
  @content_security_policy Enum.join(
                             [
                               "default-src 'self'",
                               "script-src 'self' 'sha256-BK52NP1e8rQFFVZCoDYB4YoCL0cZc/KAVl4dkMM7/QM='",
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
  end

  # The gate (#440, ADR 0004): without the session marker of the current
  # unlock only „Bitte über ratsprojekte öffnen“. LiveViews of #437 go into a
  # live_session with `on_mount: RatsprojekteWeb.Zugang`.
  pipeline :zugang do
    plug(RatsprojekteWeb.Zugang)
  end

  scope "/", RatsprojekteWeb do
    pipe_through(:browser)

    get("/zugang/:token", ZugangController, :einloesen)
  end

  scope "/", RatsprojekteWeb do
    pipe_through([:browser, :zugang])

    get("/", PageController, :home)
  end
end
