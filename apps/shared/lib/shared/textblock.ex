defmodule Shared.Textblock do
  @moduledoc """
  Ein Textblock innerhalb eines TOPs (z.B. Sachverhalt, Beschlussvorschlag).
  Der Inhalt kann HTML-codiert sein (base64 in der API).
  """

  @type t :: %__MODULE__{
          caption: String.t(),
          content: String.t(),
          mmsdataid: String.t() | nil
        }

  @derive Jason.Encoder
  defstruct [:caption, :content, :mmsdataid]
end
