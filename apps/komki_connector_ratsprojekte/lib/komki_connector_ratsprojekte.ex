defmodule KomkiConnectorRatsprojekte do
  @moduledoc """
  DURCHSTICH #409 (Wegwerf, nie gemergt): ratsprojekte-Connector — die
  komki-Seite des Wegs „Fakt vorschlagen“ (Fassung `komki-ratsprojekte/1`,
  Szene 11 des Referenzszenarios).

  Eine schreibende Operation (`fakt_vorschlagen`): Der Vermittler hat
  vorher `emit` und `store` entschieden und verlangt das GO; der
  Connector leitet den Vorschlag an den Hub weiter — dessen eigene
  schmale Schnittstelle ist ein Bandit-HTTP-Endpunkt auf einem
  Unix-Socket mit Token (#415). Der Hub kennt nur den Hash des Tokens;
  der Klartext liegt allein in der stdin-Zeile des Connectors.

  Die Quittung formuliert der CONNECTOR, nicht der Hub: Der Hub meldet
  nur Erfolg (201), „gesperrt“ (503) oder Fehler. So ist die Antwort an
  den Raum garantiert immer dieselbe — kein Schlüssel, keine Kennung,
  keine Fortnummer — und der Bestand des Hubs lässt sich nicht durch
  Antworten erraten (Szene 11: enumeration). `labels` setzt der
  Connector aus `context.assigned_label`, Gate 2 des Vermittlers prüft
  den Wert gegen die GO-Entscheidung.

  HTTP ist handgestrickt über `:gen_tcp` (eine Anfrage, Antwort bis zum
  Socket-Ende lesen, schließen) — für genau einen Pfad am eigenen Socket
  braucht es keine HTTP-Bibliothek (GO-Regel für neue Abhängigkeiten,
  AGENTS.md §1).
  """

  @behaviour Sidecar.Server

  alias KomkiConnector.Manifest
  alias KomkiPolicy.JSON

  @hub_timeout_ms 5_000
  @max_response_bytes 65_536

  @impl true
  def manifest, do: Manifest.sidecar!("ratsprojekte")

  @impl true
  def init(%{hub_socket: hub_socket, credentials: creds} = _init_arg)
      when is_binary(hub_socket) do
    case Map.fetch(creds, "KOMKI_HUB_TOKEN") do
      {:ok, token} when is_binary(token) and token != "" ->
        {:ok, %{hub_socket: hub_socket, hub_token: token}}

      _ ->
        {:error, "KOMKI_HUB_TOKEN fehlt in der stdin-Zeile"}
    end
  end

  def init(_), do: {:error, "--hub-socket fehlt"}

  @impl true
  def handle_op("fakt_vorschlagen", params, context, state) do
    body =
      JSON.canonical(%{
        "titel" => Map.fetch!(params, "titel"),
        "teile" => Map.fetch!(params, "teile"),
        "projekt_hinweis" => Map.get(params, "projekt_hinweis"),
        "labels" => context["assigned_label"]
      })

    case post(state, "/connector/fakt_vorschlagen", body) do
      {:ok, 201} ->
        {:ok, %{"status" => "vorgeschlagen", "labels" => context["assigned_label"]}}

      {:ok, 503} ->
        {:error, "hub-gesperrt", "Hub ist gesperrt, es wurde nichts gespeichert"}

      {:ok, 401} ->
        {:error, "credential-missing", "Hub lehnt das Token ab"}

      {:ok, status} ->
        {:error, "upstream-error", "Hub antwortet HTTP #{status}"}

      {:error, :timeout} ->
        {:error, "upstream-timeout", "Hub antwortet nicht"}

      {:error, reason} ->
        {:error, "upstream-error", "Hub nicht erreichbar: #{inspect(reason)}"}
    end
  end

  # -------------------------------------------------------------------------
  # HTTP über den Unix-Socket des Hubs: verbinden, eine POST-Anfrage mit
  # Connection: close, die Antwort bis zum Socket-Ende lesen, Statuszeile
  # nehmen. Der Rumpf interessiert nicht — die Quittung formuliert der
  # Connector selbst.
  # -------------------------------------------------------------------------

  defp post(state, path, body) do
    request =
      "POST " <>
        path <>
        " HTTP/1.1\r\nHost: localhost\r\nContent-Type: application/json\r\n" <>
        "Authorization: Bearer " <>
        state.hub_token <>
        "\r\nContent-Length: " <>
        Integer.to_string(byte_size(body)) <>
        "\r\nConnection: close\r\n\r\n" <> body

    with {:ok, sock} <- connect(state.hub_socket),
         :ok <- :gen_tcp.send(sock, request),
         {:ok, response} <- recv_all(sock) do
      _ = :gen_tcp.close(sock)
      status(response)
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp connect(socket) do
    case :gen_tcp.connect(
           {:local, socket},
           0,
           [:binary, packet: :raw, active: false],
           @hub_timeout_ms
         ) do
      {:ok, sock} ->
        {:ok, sock}

      {:error, :econnrefused} ->
        {:error, :timeout}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp recv_all(sock, acc \\ "") do
    case :gen_tcp.recv(sock, 0, @hub_timeout_ms) do
      {:ok, chunk} ->
        acc = acc <> chunk

        if byte_size(acc) > @max_response_bytes,
          do: {:error, :response_too_large},
          else: recv_all(sock, acc)

      {:error, :closed} ->
        {:ok, acc}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp status(response) do
    case response |> String.split("\r\n") |> List.first() |> String.split(" ") do
      [_http, code | _rest] ->
        case Integer.parse(code) do
          {status, ""} -> {:ok, status}
          _ -> {:error, :bad_status_line}
        end

      _ ->
        {:error, :bad_status_line}
    end
  end
end
