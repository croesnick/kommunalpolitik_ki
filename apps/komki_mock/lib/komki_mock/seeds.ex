defmodule KomkiMock.Seeds do
  @moduledoc """
  Seeds kept as JSON files: `priv/seeds/<system>/<name>.json`. Names are
  plain words, so a seed name can never point outside its directory.
  """

  @spec load(String.t(), String.t()) :: {:ok, term()} | :error
  def load(system, name) do
    with true <- name =~ ~r/\A[a-z0-9_-]+\z/,
         {:ok, json} <-
           File.read(Path.join([:code.priv_dir(:komki_mock), "seeds", system, name <> ".json"])) do
      {:ok, JSON.decode!(json)}
    else
      _ -> :error
    end
  end
end
