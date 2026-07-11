defmodule Shared.Dokument do
  @moduledoc """
  Ein Dokument (PDF, etc.), das an einen TOP oder eine Sitzung angehängt ist.
  """

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          fileext: String.t(),
          guestvisible: boolean(),
          lokaler_pfad: String.t() | nil,
          client_name: String.t() | nil
        }

  @derive Jason.Encoder
  defstruct [:id, :name, :fileext, :guestvisible, :lokaler_pfad, :client_name]
end
