defmodule KomkiEgress.Resolver do
  @moduledoc """
  Löst einen Hostnamen in alle IPv4- und IPv6-Adressen auf. Die
  Verbindung prüft danach jede dieser Adressen; IPv4 steht vorn, weil
  der Verbindungsaufbau sie in dieser Reihenfolge versucht.
  """

  @spec resolve(String.t()) :: {:ok, [:inet.ip_address()]} | {:error, :nxdomain}
  def resolve(host) do
    name = String.to_charlist(host)

    addresses =
      Enum.flat_map([:inet, :inet6], fn family ->
        case :inet.getaddrs(name, family) do
          {:ok, list} -> list
          {:error, _} -> []
        end
      end)

    if addresses == [], do: {:error, :nxdomain}, else: {:ok, Enum.uniq(addresses)}
  end
end
