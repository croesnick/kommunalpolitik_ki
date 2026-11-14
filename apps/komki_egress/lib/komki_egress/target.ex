defmodule KomkiEgress.Target do
  @moduledoc """
  Zerlegt und normalisiert ein Ziel `host:port`.

  Gemeinsam genutzt von der Konfiguration (Allowlist-Einträge) und vom
  CONNECT-Request, damit beide Seiten dieselbe Normalform vergleichen:
  Hostname in Kleinschreibung, Port 1..65535. IP-Literale (auch
  Kurzformen wie `127.1` und IPv6 in eckigen Klammern) werden abgelehnt,
  ebenso Wildcards und alles, was kein DNS-Name ist.
  """

  @label ~r/^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/

  @type t :: {String.t(), 1..65_535}

  @doc "Zerlegt `host:port` in `{host, port}` (Host kleingeschrieben)."
  @spec parse(String.t()) :: {:ok, t()} | {:error, :ip_literal | :malformed}
  def parse("[" <> _), do: {:error, :ip_literal}

  def parse(authority) when is_binary(authority) do
    with [host, port] <- String.split(authority, ":"),
         {:ok, port} <- parse_port(port),
         host = String.downcase(host),
         :ok <- check_host(host) do
      {:ok, {host, port}}
    else
      {:error, :ip_literal} -> {:error, :ip_literal}
      _ -> {:error, :malformed}
    end
  end

  @doc "Normalform `host:port` für den Allowlist-Vergleich."
  @spec to_string(t()) :: String.t()
  def to_string({host, port}), do: host <> ":" <> Integer.to_string(port)

  defp parse_port(text) do
    case Integer.parse(text) do
      {port, ""} when port in 1..65_535 -> {:ok, port}
      _ -> :error
    end
  end

  defp check_host(host) do
    cond do
      match?({:ok, _}, :inet.parse_address(String.to_charlist(host))) -> {:error, :ip_literal}
      byte_size(host) in 1..253 and host |> String.split(".") |> Enum.all?(&(&1 =~ @label)) -> :ok
      true -> :error
    end
  end
end
