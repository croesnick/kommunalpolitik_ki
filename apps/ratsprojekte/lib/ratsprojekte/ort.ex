defmodule Ratsprojekte.Ort do
  @moduledoc """
  Where the hub keeps its files (ADR 0004 „Lokal, ohne Konten“): one
  directory, by default `~/Library/Application Support/ratsprojekte/`,
  `RATSPROJEKTE_HOME` overrides it (throwaway instances). The directory is
  created with mode 0700, so the sockets inside are reachable only for the
  user even before their own mode is set.

  Time Machine backs up the whole directory. It sees only ciphertext: the
  database is SQLCipher, the key is sealed to this Mac's Secure Enclave.
  """

  @doc "The configured home directory."
  @spec home() :: String.t()
  def home do
    Application.get_env(:ratsprojekte, :home) ||
      Path.join(System.user_home!(), "Library/Application Support/ratsprojekte")
  end

  # macOS limits Unix socket paths to 104 bytes including the terminator.
  @max_socket_pfad 103

  @doc "Do the socket paths under `home` fit the Unix socket limit?"
  @spec passt?(String.t()) :: boolean()
  def passt?(home),
    do:
      byte_size(connector(home)) <= @max_socket_pfad and
        byte_size(verwaltung(home)) <= @max_socket_pfad

  @doc "Create the home directory (0700); refuses a home whose sockets would not fit."
  @spec anlegen!(String.t()) :: :ok
  def anlegen!(home) do
    # The message names no path (logs carry none).
    unless passt?(home),
      do: raise(ArgumentError, "RATSPROJEKTE_HOME ist zu lang für die Sockets (macOS: 103 Bytes)")

    File.mkdir_p!(home)
    File.chmod!(home, 0o700)
  end

  @spec datenbank(String.t()) :: String.t()
  def datenbank(home), do: Path.join(home, "ratsprojekte.db")

  @doc "The copy taken before a schema change; only the latest is kept."
  @spec kopie(String.t()) :: String.t()
  def kopie(home), do: Path.join(home, "ratsprojekte.db.vor-migration")

  @doc "The database key, sealed to the Secure Enclave (`ktv2`)."
  @spec schluessel(String.t()) :: String.t()
  def schluessel(home), do: Path.join(home, "schluessel.ktv2")

  @doc "SHA-256 (hex) of the connector token; the plaintext lives only in komki's keychain."
  @spec token_hash(String.t()) :: String.t()
  def token_hash(home), do: Path.join(home, "connector-token.sha256")

  @doc "Socket for the `ratsprojekte` command (open, lock, status)."
  @spec verwaltung(String.t()) :: String.t()
  def verwaltung(home), do: Path.join(home, "verwaltung.sock")

  @doc "Socket for the komki connector; connector operations only."
  @spec connector(String.t()) :: String.t()
  def connector(home), do: Path.join(home, "connector.sock")

  @doc "Write `content` atomically with mode 0600."
  @spec schreiben!(String.t(), iodata()) :: :ok
  def schreiben!(path, content) do
    tmp = path <> ".tmp"
    File.write!(tmp, content)
    File.chmod!(tmp, 0o600)
    File.rename!(tmp, path)
  end
end
