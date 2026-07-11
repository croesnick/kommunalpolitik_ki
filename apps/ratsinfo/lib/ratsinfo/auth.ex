defmodule Ratsinfo.Auth do
  @moduledoc """
  Auth-Helper: Einloggen, Token cachen, wiederverwenden.

  Token wird in ~/.config/kommunalpolitik_ki/token gespeichert
  (außerhalb des Repos, sicher).
  """

  alias Ratsinfo.{ApiClient, Config}

  @token_file "token"

  @doc """
  Holt einen gültigen Token — aus Cache oder via Login.
  """
  @spec get_token() :: {:ok, String.t()} | {:error, term()}
  def get_token do
    case read_cached_token() do
      {:ok, token} when is_binary(token) and byte_size(token) > 10 ->
        {:ok, token}

      _ ->
        login_fresh()
    end
  end

  @doc "Erzwinge frischen Login"
  @spec login_fresh() :: {:ok, String.t()} | {:error, term()}
  def login_fresh do
    {email, password} = Config.credentials()

    cond do
      is_nil(email) or is_nil(password) ->
        {:error, :no_credentials}

      email == "" or password == "" ->
        {:error, :no_credentials}

      true ->
        case ApiClient.login(email, password) do
          {:ok, token} ->
            save_token(token)
            {:ok, token}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  defp token_path do
    Path.join(System.user_home!(), ".config/kommunalpolitik_ki/#{@token_file}")
  end

  defp read_cached_token do
    path = token_path()

    if File.exists?(path) do
      case File.read(path) do
        {:ok, content} -> {:ok, String.trim(content)}
        _ -> :error
      end
    else
      :error
    end
  end

  defp save_token(token) do
    path = token_path()
    dir = Path.dirname(path)
    File.mkdir_p!(dir)
    File.write!(path, token)
  end
end
