defmodule Shared.Suchergebnis do
  @moduledoc """
  Ein Treffer aus der RIS-Volltextsuche.
  Kann ein TOP (agendaitem), ein Dokument oder ein Sitzungsdokument sein.
  """

  @type t :: %__MODULE__{
          id: String.t(),
          sitzung_id: integer() | nil,
          gremium_id: integer() | nil,
          titel: String.t(),
          sitzung_name: String.t() | nil,
          datum: Date.t() | nil,
          nummer: String.t() | nil,
          client_name: String.t() | nil,
          restricted: boolean() | nil
        }

  @derive Jason.Encoder
  defstruct [
    :id,
    :sitzung_id,
    :gremium_id,
    :titel,
    :sitzung_name,
    :datum,
    :nummer,
    :client_name,
    :restricted
  ]
end
