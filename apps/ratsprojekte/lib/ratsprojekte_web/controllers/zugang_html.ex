defmodule RatsprojekteWeb.ZugangHTML do
  @moduledoc "The page for everyone without access to the hub."

  use RatsprojekteWeb, :html

  def bitte_oeffnen(assigns) do
    ~H"""
    <main id="bitte-oeffnen" class="mx-auto max-w-md px-6 py-24 text-center">
      <h1 class="text-xl font-semibold">Bitte über ratsprojekte öffnen</h1>
      <p class="mt-4 opacity-70">
        Der Hub ist gesperrt oder dieser Tab hat keinen Zugang. Im Terminal
        <code>ratsprojekte open</code> eingeben.
      </p>
    </main>
    """
  end
end
