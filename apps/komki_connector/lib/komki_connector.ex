defmodule KomkiConnector do
  @moduledoc """
  Gemeinsame Grundlage der komki-Connectoren (CONTRACT.md): das
  Frame-Protokoll ueber Unix-Sockets lebt seit Ticket #225 in der Library
  `apps/sidecar` (`Sidecar.Frame`, `Sidecar.Client`, `Sidecar.Server`,
  `Sidecar.Token`, `Sidecar.Params`, `Sidecar.Peer`). Hier bleiben die
  komki-spezifischen Teile: die Manifeste als einzige Quelle fuer
  Fassung, Operationen, Netz, Dateisystem, Credentials und Import-Labels
  (`KomkiConnector.Manifest`), die CA-Zertifikate der Connectoren
  (`KomkiConnector.TLS`), die deutschen Modell-Texte
  (`KomkiConnector.Text`) und der Start-Einstieg
  (`KomkiConnector.Launch`).
  """
end
