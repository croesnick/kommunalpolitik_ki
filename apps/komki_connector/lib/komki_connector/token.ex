defmodule KomkiConnector.Token do
  @moduledoc """
  Capability-Token je Connector-Start (CONTRACT.md §3, §4).

  Der Connector-Socket ist `0600` und fuer pis Sandbox unerreichbar. Das
  allein vertraut aber jedem anderen Prozess derselben uid. Deshalb
  verlangt jeder Connector in jeder Anfrage ein Token, das `komki up` vor
  dem Start zufaellig erzeugt: Der Connector bekommt es ueber stdin, der
  Vermittler liest es aus `<base>/run/connectors/<id>.token` (`0600`).
  Verglichen wird in konstanter Zeit. Das Token steht nie in argv,
  Umgebung, Log oder Antworten.
  """

  @bytes 32

  @doc "Name des reservierten Eintrags in der stdin-Zeile des Connectors."
  @spec credential_key() :: String.t()
  def credential_key, do: "KOMKI_CONNECTOR_TOKEN"

  @doc "Neues Token: 32 Byte Zufall als Hex."
  @spec generate() :: String.t()
  def generate, do: Base.encode16(:crypto.strong_rand_bytes(@bytes), case: :lower)

  @doc "Tokendatei des Connectors `id` neben seinem Socket."
  @spec path(Path.t(), String.t()) :: Path.t()
  def path(connectors_dir, id), do: Path.join(connectors_dir, id <> ".token")

  @doc "Tokendatei zum Connector-Socket `<dir>/<id>.sock`: `<dir>/<id>.token`."
  @spec for_socket(Path.t()) :: Path.t()
  def for_socket(socket_path), do: Path.rootname(socket_path) <> ".token"

  @doc "Token mit Rechten `0600` schreiben (vorher angelegt, dann befuellt)."
  @spec write!(Path.t(), String.t()) :: :ok
  def write!(path, token) do
    _ = File.rm(path)
    File.write!(path, "", [:exclusive])
    File.chmod!(path, 0o600)
    File.write!(path, token)
  end

  @doc "Neues Token fuer den Connector an `socket_path` erzeugen und ablegen."
  @spec provision!(Path.t()) :: String.t()
  def provision!(socket_path) do
    token = generate()
    write!(for_socket(socket_path), token)
    token
  end

  @doc "Token lesen; `:error`, wenn die Datei fehlt oder kein Token enthaelt."
  @spec read(Path.t()) :: {:ok, String.t()} | :error
  def read(path) do
    case File.read(path) do
      {:ok, token} -> if valid?(token), do: {:ok, token}, else: :error
      {:error, _} -> :error
    end
  end

  @doc "Formal gueltiges Token (64 Hex-Zeichen)?"
  @spec valid?(term()) :: boolean()
  def valid?(token), do: is_binary(token) and token =~ ~r/\A[0-9a-f]{64}\z/

  @doc "Vergleich in konstanter Zeit; ungueltige Werte sind nie gleich."
  @spec equal?(term(), String.t()) :: boolean()
  def equal?(given, expected) do
    valid?(given) and valid?(expected) and :crypto.hash_equals(given, expected)
  end
end
