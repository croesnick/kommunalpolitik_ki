defmodule KomkiMediator.Tools.RpStandLesen do
  @moduledoc """
  MCP tool `rp_stand_lesen` (#419, Szene 12): reads the stand the
  ratsprojekte hub last put out (connector ratsprojekte, operation
  stand_lesen). Description from the manifest, no parameters. The call is
  admit-only (`KomkiMediator.ConnectorGate`, contract §6.4): the engine
  decides whether `ratsprojekte@1` may enter this room before the connector
  reads the file, and there is no GO on this path.
  """

  use KomkiMediator.Tools.Connector, tool: "rp_stand_lesen"
end
