defmodule RatsprojekteWeb.Plugs.Nav do
  @moduledoc """
  Stellt assigns für die globale Navigation bereit, die im Root-Layout
  gerendert wird.

  Da das Root-Layout außerhalb der LiveViews vom Plug-Stack gerendert wird,
  kann es nicht auf LiveView-Assigns zugreifen. Dieser Plug setzt:

    * `:pending_count` — Anzahl aller offenen AI-Vorschläge (pending),
      egal ob Top-Level (add_projekt) oder pro-Projekt (add_realisierungsstrang).
      Bestimmt das amber-farbene Badge an „Vorschläge".
    * `:nav_section` — kurzes Token, welcher Navigationsbereich aktiv ist
      (`:projekte`, `:vorschlaege` oder `nil`). Der Root-Layout nutzt das
      für die Active-State-Hervorhebung.

  Der Plug wird in der `:browser`-Pipeline des Routers ausgeführt.
  """

  @behaviour Plug

  import Plug.Conn
  import Ecto.Query

  alias Ratsprojekte.Repo
  alias Ratsprojekte.Schemas.PendingProposal

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    pending_count = count_pending_proposals()
    nav_section = derive_section(conn.path_info)

    conn
    |> assign(:pending_count, pending_count)
    |> assign(:nav_section, nav_section)
  end

  defp count_pending_proposals do
    PendingProposal
    |> where(status: :pending)
    |> Repo.aggregate(:count)
  end

  # "/"            → :projekte
  # "/projekte/…"  → :projekte
  # "/proposals"   → :vorschlaege
  # "/proposals/…" → :vorschlaege
  # geschachtelte "/projekte/:id/proposals" gehören logisch zum Projekt → :projekte
  # alles andere (z.B. /mcp) → nil (kein Active-State)
  defp derive_section([]), do: :projekte
  defp derive_section(["projekte" | _]), do: :projekte
  defp derive_section(["proposals" | _]), do: :vorschlaege
  defp derive_section(_), do: nil
end
