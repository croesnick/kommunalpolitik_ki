defmodule KomkiEgress.Config do
  @moduledoc """
  Liest die Startkonfiguration (eine JSON-Zeile von stdin, CONTRACT §9):

      {"ports": {"<port>": {"connector": "web", "allow": ["api.search.brave.com:443"]}}}

  Ergebnis ist eine Map `port => %{connector: name, allow: MapSet}` mit
  Allowlist-Einträgen in Normalform (`KomkiEgress.Target`). Unbekannte
  Schlüssel, leere Listen, Wildcards und IP-Literale sind Fehler: lieber
  gar nicht starten als eine unklare Allowlist durchsetzen.
  """

  alias KomkiEgress.Target

  @connector ~r/^[a-z][a-z0-9_-]{0,63}$/

  @type entry :: %{connector: String.t(), allow: MapSet.t(String.t())}
  @type t :: %{pos_integer() => entry()}

  @doc "Parst die JSON-Zeile; Fehler als lesbare deutsche Meldung."
  @spec parse(String.t()) :: {:ok, t()} | {:error, String.t()}
  def parse(line) when is_binary(line) do
    with {:ok, decoded} <- decode(line),
         {:ok, ports} <- fetch_ports(decoded) do
      parse_ports(ports)
    end
  end

  defp parse_ports(ports) do
    Enum.reduce_while(ports, {:ok, %{}}, fn {port, entry}, {:ok, acc} ->
      case parse_port_entry(port, entry) do
        {:ok, port, parsed} -> {:cont, {:ok, Map.put(acc, port, parsed)}}
        {:error, message} -> {:halt, {:error, message}}
      end
    end)
  end

  defp decode(line) do
    case JSON.decode(String.trim(line)) do
      {:ok, decoded} -> {:ok, decoded}
      {:error, _} -> {:error, "Konfiguration ist kein gültiges JSON"}
    end
  end

  defp fetch_ports(%{"ports" => ports} = map) when map_size(map) == 1 and is_map(ports) do
    if map_size(ports) == 0,
      do: {:error, "\"ports\" ist leer"},
      else: {:ok, Enum.sort(ports)}
  end

  defp fetch_ports(_), do: {:error, "erwartet genau ein Objekt {\"ports\": {...}}"}

  defp parse_port_entry(port_text, entry) do
    with {:ok, port} <- parse_port(port_text),
         {:ok, connector, allow} <- fetch_entry(port, entry),
         {:ok, allow} <- parse_allow(port, allow) do
      {:ok, port, %{connector: connector, allow: allow}}
    end
  end

  defp parse_port(text) do
    case Integer.parse(text) do
      {port, ""} when port in 1..65_535 -> {:ok, port}
      _ -> {:error, "Port #{inspect(text)} ist keine Portnummer (1..65535)"}
    end
  end

  defp fetch_entry(port, %{"connector" => connector, "allow" => allow} = entry)
       when map_size(entry) == 2 and is_binary(connector) and is_list(allow) and allow != [] do
    if connector =~ @connector,
      do: {:ok, connector, allow},
      else: {:error, "Port #{port}: ungültiger Connector-Name #{inspect(connector)}"}
  end

  defp fetch_entry(port, _) do
    {:error,
     ~s(Port #{port}: erwartet genau {"connector": "<name>", "allow": ["host:port", ...]} ) <>
       "mit nicht leerer Liste"}
  end

  defp parse_allow(port, allow) do
    Enum.reduce_while(allow, {:ok, MapSet.new()}, fn item, {:ok, acc} ->
      case parse_target(item) do
        {:ok, target} ->
          {:cont, {:ok, MapSet.put(acc, Target.to_string(target))}}

        {:error, reason} ->
          {:halt, {:error, "Port #{port}: Allowlist-Eintrag #{inspect(item)} #{reason}"}}
      end
    end)
  end

  defp parse_target(item) when is_binary(item) do
    case Target.parse(item) do
      {:ok, target} -> {:ok, target}
      {:error, :ip_literal} -> {:error, "ist ein IP-Literal (nur Hostnamen erlaubt)"}
      {:error, :malformed} -> {:error, "ist nicht der Form host:port"}
    end
  end

  defp parse_target(_), do: {:error, "ist kein String"}
end
