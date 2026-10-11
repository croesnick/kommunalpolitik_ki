defmodule Shared.Sitzung do
  @moduledoc """
  Eine Sitzung im Ratsinformationssystem (z.B. Stadtratssitzung, Ausschusssitzung).
  """

  alias Shared.{Gremium, TOP}

  @type t :: %__MODULE__{
          id: integer(),
          name: String.t(),
          gremium: Gremium.t() | nil,
          datum: Date.t() | nil,
          ort: String.t() | nil,
          status: atom(),
          oeffentlich: boolean(),
          teilsoeffentlich: boolean(),
          oeffentliche_startzeit: String.t() | nil,
          oeffentliche_endzeit: String.t() | nil,
          nichtoeffentliche_startzeit: String.t() | nil,
          nichtoeffentliche_endzeit: String.t() | nil,
          tops: [TOP.t()],
          dokumente: [Shared.Dokument.t()],
          client_id: integer(),
          client_name: String.t() | nil
        }

  @derive Jason.Encoder
  defstruct [
    :id,
    :name,
    :gremium,
    :datum,
    :ort,
    :status,
    :oeffentlich,
    :teilsoeffentlich,
    :oeffentliche_startzeit,
    :oeffentliche_endzeit,
    :nichtoeffentliche_startzeit,
    :nichtoeffentliche_endzeit,
    :tops,
    :dokumente,
    :client_id,
    :client_name
  ]
end
