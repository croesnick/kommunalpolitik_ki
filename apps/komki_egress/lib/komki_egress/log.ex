defmodule KomkiEgress.Log do
  @moduledoc """
  Eine JSON-Zeile je Verbindung auf stderr: Port, Connector, Ziel
  (`host:port`, sofern ein CONNECT geparst wurde), verbundene Adresse,
  Entscheidung, Ablehnungsgrund, Bytes hin und zurück, Dauer. Nie Inhalte:
  weder Nutzdaten noch Kopfzeilen noch die Request-Zeile anderer Methoden.
  """

  @spec write(map()) :: :ok
  def write(record) do
    IO.puts(:stderr, JSON.encode!(Map.put(record, :event, "connection")))
  end
end
