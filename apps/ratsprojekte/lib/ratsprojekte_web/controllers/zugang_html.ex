defmodule RatsprojekteWeb.ZugangHTML do
  @moduledoc "The lock page: everyone without access sees only this."

  use RatsprojekteWeb, :html

  attr(:fehler, :string, default: nil)
  attr(:pruefcode, :string, required: true)

  def gesperrt(assigns) do
    ~H"""
    <main id="gesperrt" class="mx-auto flex min-h-screen max-w-sm flex-col justify-center px-6 text-center">
      <.icon name="hero-lock-closed" class="mx-auto size-10 opacity-60" />
      <h1 class="mt-4 text-xl font-semibold">Der Hub ist gesperrt</h1>
      <p class="mt-2 opacity-70">Nach dem Klick fragt macOS nach Touch ID oder dem Passwort.</p>

      <p class="mt-6 text-lg font-semibold">
        Prüfcode <code id="pruefcode" class="tracking-widest">{@pruefcode}</code>
      </p>
      <p class="mt-1 text-sm opacity-70">Nur freigeben, wenn der Dialog denselben Prüfcode zeigt.</p>

      <.form for={%{}} action={~p"/entsperren"} id="entsperren-form" class="mt-8">
        <input type="hidden" name="pruefcode" value={@pruefcode} />
        <button id="entsperren" type="submit" class="btn btn-primary w-full">Entsperren</button>
      </.form>

      <p :if={@fehler} id="entsperren-fehler" class="mt-4 text-error">{@fehler}</p>

      <p class="mt-8 text-sm opacity-50">Im Terminal geht es auch: <code>ratsprojekte open</code></p>
    </main>
    """
  end
end
