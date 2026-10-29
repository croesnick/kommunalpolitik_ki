# Gemeinsamer HTTP-Sockel-Kram fuer mock_ris.exs und ris_recorder.exs.
#
# Beide Skripte sind eigenstaendig startbar und laden diese Datei per
# Code.require_file — weiterhin nur OTP, keine Deps. Hier lebt, was sonst in
# beiden Skripten dupliziert waere (und der Body-Bug dann doppelt drin):

defmodule KomkiConnectorRis.RisHttp do
  @moduledoc false

  @timeout 5_000

  @doc """
  Liest eine HTTP-Anfrage vom Sockel: `{:ok, Methode, Pfad, Kopfzeilen, Body}`
  oder `:error`. Der Body wird komplett gelesen (auch wenn ihn nur der
  Recorder braucht): ein Socket mit ungelesenen Daten sendet beim Schliessen
  RST, die Antwort kaeme beim Client nie an.
  """
  @spec read_request(:gen_tcp.socket()) ::
          {:ok, atom() | String.t(), String.t(), [{String.t(), String.t()}], binary()} | :error
  def read_request(sock) do
    case :gen_tcp.recv(sock, 0, @timeout) do
      {:ok, {:http_request, method, {:abs_path, target}, _version}} ->
        case read_headers(sock, []) do
          {:ok, headers} -> read_body(sock, method, target, headers)
          :error -> :error
        end

      _ ->
        :error
    end
  end

  defp read_headers(sock, acc) do
    case :gen_tcp.recv(sock, 0, @timeout) do
      {:ok, :http_eoh} ->
        {:ok, Enum.reverse(acc)}

      {:ok, {:http_header, _, key, _, value}} ->
        read_headers(sock, [{header_name(key), value} | acc])

      _ ->
        :error
    end
  end

  # Laengenbasiertes recv ist nur im Raw-Modus erlaubt; auf einem
  # packet: :http_bin Sockel liefert es :einval. Nach dem Kopfzeilenende
  # deshalb auf :raw umschalten, bevor der Body gelesen wird.
  defp read_body(sock, method, target, headers) do
    case header(headers, "content-length") do
      nil ->
        {:ok, method, target, headers, ""}

      value ->
        case Integer.parse(value) do
          {n, _rest} when n > 0 ->
            :ok = :inet.setopts(sock, packet: :raw)

            case :gen_tcp.recv(sock, n, @timeout) do
              {:ok, body} -> {:ok, method, target, headers, body}
              _ -> :error
            end

          _ ->
            {:ok, method, target, headers, ""}
        end
    end
  end

  @doc "Wert der ersten Kopfzeile mit `name` (kleingeschrieben) oder `nil`."
  @spec header([{String.t(), String.t()}], String.t()) :: String.t() | nil
  def header(headers, name) do
    Enum.find_value(headers, fn
      {^name, value} -> value
      _other -> nil
    end)
  end

  # Ohne List.keyfind: dessen Position-Semantik hat sich in Elixir 1.20
  # geaendert (0-basiert, Default nil statt false).

  # Bekannte Kopfzeilen kommen als Atom, unbekannte (X-Orgkey & Co.) als
  # Binaer-String oder Zeichenliste (auch :httpc-Antworten nutzen das Format).
  @doc false
  @spec header_name(atom() | String.t() | charlist()) :: String.t()
  def header_name(key) when is_atom(key), do: key |> Atom.to_string() |> String.downcase()
  def header_name(key) when is_binary(key), do: String.downcase(key)
  def header_name(key) when is_list(key), do: key |> List.to_string() |> String.downcase()

  @doc "Pfad und Query eines Anfrageziels (`/pfad?a=b` → `{\"/pfad\", \"a=b\"}`)."
  @spec split_target(String.t()) :: {String.t(), String.t() | nil}
  def split_target(target) do
    case String.split(target, "?", parts: 2) do
      [path] -> {path, nil}
      [path, query] -> {path, query}
    end
  end

  @doc """
  Methodenname als String. Standardmethoden liefert das HTTP-Paket als Atom,
  ungewoehnliche (z. B. PROPFIND) als Binaer-String — beide werden hier
  normalisiert, damit Atom.to_string nirgends crasht.
  """
  @spec method_label(atom() | String.t()) :: String.t()
  def method_label(method) when is_atom(method), do: Atom.to_string(method)
  def method_label(method) when is_binary(method), do: method
end
