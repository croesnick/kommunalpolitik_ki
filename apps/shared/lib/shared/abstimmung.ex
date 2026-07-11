defmodule Shared.Abstimmung do
  @moduledoc """
  Eine Abstimmung zu einem TOP (Struktur TBD — API liefert bisher leere votings-Arrays).
  """

  @type t :: %__MODULE__{
          id: String.t() | nil,
          ergebnis: String.t() | nil
        }

  @derive Jason.Encoder
  defstruct [:id, :ergebnis]
end
