defmodule Shared.Gremium do
  @moduledoc """
  Ein Gremium (Ausschuss, Rat, Versammlung) im Ratsinformationssystem.
  """

  @type t :: %__MODULE__{
          id: integer(),
          name: String.t(),
          client_id: integer()
        }

  @derive Jason.Encoder
  defstruct [:id, :name, :client_id]
end
