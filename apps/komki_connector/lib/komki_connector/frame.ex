defmodule KomkiConnector.Frame do
  @moduledoc """
  Frame-Protokoll v1 (CONTRACT.md §3): 4 Byte Laenge (Big Endian, das
  `packet: 4` von `:gen_tcp`), dann UTF-8-JSON. Hoechstens 1 MiB je Frame.

  Diese Funktionen kodieren und dekodieren nur den JSON-Teil; das
  Laengenpraefix setzt `:gen_tcp` (`packet: 4`, `packet_size`).
  """

  @version 1
  @max_bytes 1_048_576

  @error_codes ~w(bad-request unknown-op not-found upstream-error upstream-timeout
                  credential-missing forbidden-path too-large unauthorized internal)

  @doc "Protokollversion."
  @spec version() :: pos_integer()
  def version, do: @version

  @doc "Groesste zulaessige Frame-Laenge in Byte."
  @spec max_bytes() :: pos_integer()
  def max_bytes, do: @max_bytes

  @doc "Geschlossene Menge der Fehlercodes."
  @spec error_codes() :: [String.t()]
  def error_codes, do: @error_codes

  @doc """
  Fester Text je Fehlercode. Nur dieser Text erreicht den Vermittler und
  damit das Modell; was ein Connector selbst als `detail` schreibt, bleibt
  in dessen Log.
  """
  @spec describe(String.t()) :: String.t()
  def describe("bad-request"), do: "Anfrage ungültig"
  def describe("unknown-op"), do: "unbekannte Operation"
  def describe("not-found"), do: "nicht gefunden"
  def describe("upstream-error"), do: "Fehler beim angebundenen Dienst"
  def describe("upstream-timeout"), do: "angebundener Dienst antwortet nicht"
  def describe("credential-missing"), do: "Zugangsdaten fehlen"
  def describe("forbidden-path"), do: "Pfad nicht erlaubt"
  def describe("too-large"), do: "Antwort oder Anfrage zu groß"
  def describe("unauthorized"), do: "Aufruf nicht berechtigt"
  def describe(_code), do: "interner Fehler"

  @doc "Socket-Optionen fuer beide Seiten (Laengenpraefix plus Groessengrenze)."
  @spec socket_opts() :: list()
  def socket_opts, do: [:binary, packet: 4, packet_size: @max_bytes, active: false]

  @doc "Anfrage-Frame bauen; `token` ist das Capability-Token des Connectors."
  @spec request(String.t(), String.t(), String.t(), map(), map()) :: map()
  def request(token, call_id, op, params, context \\ %{}) do
    base = %{
      "v" => @version,
      "token" => token,
      "call_id" => call_id,
      "op" => op,
      "params" => params
    }

    if context == %{}, do: base, else: Map.put(base, "context", context)
  end

  @doc "Erfolgs-Antwort bauen."
  @spec ok(String.t(), map()) :: map()
  def ok(call_id, result),
    do: %{"v" => @version, "call_id" => call_id, "ok" => true, "result" => result}

  @doc "Fehler-Antwort bauen; unbekannte Codes werden zu `internal`."
  @spec error(String.t(), String.t(), String.t()) :: map()
  def error(call_id, code, detail) do
    code = if code in @error_codes, do: code, else: "internal"

    %{
      "v" => @version,
      "call_id" => call_id,
      "ok" => false,
      "error" => %{"code" => code, "detail" => detail}
    }
  end

  @doc "JSON-Kodierung eines Frames."
  @spec encode(map()) :: {:ok, binary()} | {:error, :too_large}
  def encode(map) do
    bin = map |> :json.encode() |> IO.iodata_to_binary()
    if byte_size(bin) > @max_bytes, do: {:error, :too_large}, else: {:ok, bin}
  end

  @doc """
  JSON-Dekodierung eines Frames. Verlangt ein Objekt mit `"v" == 1`;
  alles andere ist `{:error, :bad_frame}`.
  """
  @spec decode(binary()) :: {:ok, map()} | {:error, :bad_frame}
  def decode(bin) when is_binary(bin) do
    case safe_decode(bin) do
      {:ok, %{"v" => @version} = map} -> {:ok, map}
      _ -> {:error, :bad_frame}
    end
  end

  defp safe_decode(bin) do
    {:ok, :json.decode(bin)}
  rescue
    _ -> {:error, :bad_frame}
  end
end
