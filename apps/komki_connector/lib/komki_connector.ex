defmodule KomkiConnector do
  @moduledoc """
  Gemeinsame Grundlage der komki-Connectoren (CONTRACT.md): Frame-Protokoll
  ueber Unix-Sockets (`KomkiConnector.Frame`, `Client`, `Server`), die
  Manifeste als einzige Quelle fuer Fassung, Operationen, Netz,
  Dateisystem, Credentials und Import-Labels (`KomkiConnector.Manifest`)
  sowie die Parameter-Pruefung gegen die Manifest-Schemas
  (`KomkiConnector.Params`).
  """
end
