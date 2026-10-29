defmodule KomkiConnector.Launch do
  @moduledoc """
  komki-Einstiegspunkt fuer den Start eines Connectors als Sidecar
  (CONTRACT.md §4): der Schluessel der Stdin-Zeile fuer das Token und
  `Sidecar.Server.run/5` mit den komki-Optionen, an einer Stelle
  gebuendelt, damit alle vier Connectoren identisch starten.

  `peer_credentials: true` weist Verbindungen zurueck, deren Peer-uid
  nicht die eigene ist — zusätzlich zum Token, wirksam gegen andere
  Prozesse derselben uid (Issue #225).
  """

  alias Sidecar.Server

  @credential_key "KOMKI_CONNECTOR_TOKEN"

  @doc "Schluessel des Connector-Tokens in der Stdin-Zeile (CONTRACT.md §4)."
  @spec credential_key() :: String.t()
  def credential_key, do: @credential_key

  @doc """
  Startet den Connector: Token aus der Stdin-Zeile pruefen (fail-closed),
  Socket binden, Anfragen bedienen. `{:error, :invalid_token}` wird wie
  frueher als deutscher Fehlertext uebersetzt, den die Connector-CLIs
  auf stderr ausgeben.
  """
  @spec run(module(), Path.t(), term(), map()) ::
          no_return() | {:error, String.t() | term()}
  def run(module, socket_path, init_arg, creds) do
    translate(
      Server.run(module, socket_path, init_arg, creds,
        credential_key: credential_key(),
        peer_credentials: true
      )
    )
  end

  defp translate({:error, :invalid_token}), do: {:error, "kein gueltiges Connector-Token"}
  defp translate(other), do: other
end
