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

  Prüft JWT-Ablauf (exp-Claim) und erzwingt frischen Login bei abgelaufenem Token.
  """
  @spec get_token() :: {:ok, String.t()} | {:error, term()}
  def get_token do
    case read_cached_token() do
      {:ok, token} when is_binary(token) and byte_size(token) > 10 ->
        if token_expired?(token) do
          login_fresh()
        else
          {:ok, token}
        end

      _ ->
        login_fresh()
    end
  end

  # Prüft den exp-Claim eines JWT. Wenn kein exp vorhanden oder unparseierbar,
  # vertrauen wir dem Token (lieber versuchen als blockieren).
  defp token_expired?(token) do
    case jwt_payload(token) do
      {:ok, %{"exp" => exp}} when is_integer(exp) ->
        System.system_time(:second) >= exp

      _ ->
        false
    end
  end

  defp jwt_payload(token) do
    case token |> String.split(".") |> Enum.at(1) do
      nil -> {:error, :no_payload}
      payload -> decode_jwt_payload(payload)
    end
  end

  defp decode_jwt_payload(payload) do
    padding = 4 - rem(byte_size(payload), 4)
    padded = payload <> String.duplicate("=", rem(padding, 4))

    case Base.url_decode64(padded, padding: false) do
      {:ok, json} -> Jason.decode(json)
      _ -> {:error, :invalid_base64}
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

  @doc """
  Hole einen gültigen Token — aus Cache oder via Login.

  Bei 401 (Token abgelaufen oder ungültig) automatisch frisch einloggen.
  """
  @spec with_token((String.t() -> result)) :: result when result: var
  def with_token(fun) when is_function(fun, 1) do
    with {:ok, token} <- get_token(),
         {:error, {:http_error, 401}} <- fun.(token) do
      with {:ok, fresh_token} <- login_fresh(), do: fun.(fresh_token)
    else
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
      result -> result
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
