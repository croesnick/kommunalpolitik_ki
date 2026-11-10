defmodule KomkiMediator.Tools.RpFaktVorschlagen do
  @moduledoc """
  DURCHSTICH #409 (Wegwerf): MCP tool `rp_fakt_vorschlagen` — Fakten aus
  oeffentlicher Recherche in den ratsprojekte-Hub vorschlagen (connector
  ratsprojekte, operation fakt_vorschlagen, Szene 11). Schema und
  Beschreibung kommen aus dem Manifest; der Aufruf laeuft als
  emit → store → Vollzug → admit (`KomkiMediator.ConnectorGate`): ohne
  `store`-Regel in Γ braucht jedes Vorschreiben ein GO, und der
  Empfaengertest des Hubs laesst sich durch kein GO ersetzen (#417).
  """

  use KomkiMediator.Tools.Connector, tool: "rp_fakt_vorschlagen"
end
