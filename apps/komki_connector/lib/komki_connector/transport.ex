defmodule KomkiConnector.Transport do
  @moduledoc """
  Which transports may carry a secret (an API key, a login) from a
  connector to its upstream: `https` always, `http` only to loopback hosts
  (`localhost`, `127.0.0.0/8`, `::1`), which is how the mocks run. Cleartext
  to any other host would hand the secret to whoever holds that port (#496,
  #148).
  """

  @doc "Whether `url` may carry a secret."
  @spec secret_ok?(String.t()) :: boolean()
  def secret_ok?(url) do
    case URI.new(url) do
      {:ok, %URI{scheme: "https", host: host}} when is_binary(host) and host != "" -> true
      {:ok, %URI{scheme: "http", host: host}} -> loopback_host?(host)
      _ -> false
    end
  end

  defp loopback_host?("localhost"), do: true
  defp loopback_host?(host) when is_binary(host), do: loopback_address?(host)
  defp loopback_host?(_host), do: false

  defp loopback_address?(host) do
    case :inet.parse_address(String.to_charlist(host)) do
      {:ok, {127, _, _, _}} -> true
      {:ok, {0, 0, 0, 0, 0, 0, 0, 1}} -> true
      _ -> false
    end
  end
end
