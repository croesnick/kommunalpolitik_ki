defmodule Shared.TOP do
  @moduledoc """
  Ein Tagesordnungspunkt (TOP) innerhalb einer Sitzung.
  """

  alias Shared.{Abstimmung, Dokument, Textblock}

  @type t :: %__MODULE__{
          id: String.t(),
          sitzung_id: integer(),
          nummer: String.t(),
          titel: String.t(),
          restricted: boolean(),
          dokumente: [Dokument.t()],
          textbloecke: [Textblock.t()],
          abstimmungen: [Abstimmung.t()],
          download_allowed: boolean()
        }

  @derive Jason.Encoder
  defstruct [
    :id,
    :sitzung_id,
    :nummer,
    :titel,
    :restricted,
    :dokumente,
    :textbloecke,
    :abstimmungen,
    :download_allowed
  ]
end
