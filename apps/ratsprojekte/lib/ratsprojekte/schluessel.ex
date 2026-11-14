defmodule Ratsprojekte.Schluessel do
  @moduledoc """
  The SQLCipher key of the hub (ADR 0004): 32 random bytes, used as a raw
  key (no passphrase derivation). On disk it exists only sealed with
  `SealedEnvelope` to the hub's own Secure Enclave key (`Ort.schluessel/1`).

  The recovery code is the same key as Base32 in groups of four, shown once
  at setup; it belongs in the password manager. `ratsprojekte recover`
  seals it again, for example on a new Mac after a Time Machine restore.

  `provider` is a `SealedEnvelope` provider, in operation
  `{Ratsprojekte.Tresor, reason: ...}`, in tests the file test double.
  """

  alias Ratsprojekte.Ort

  @bytes 32

  @type error ::
          :nicht_eingerichtet
          | :schon_eingerichtet
          | :falscher_code
          | :falscher_schluessel
          | {:tresor, term()}

  @doc "A fresh key."
  @spec neu() :: binary()
  def neu, do: :crypto.strong_rand_bytes(@bytes)

  @doc """
  The value for `PRAGMA key` (the `:key` option of exqlite, which inserts
  it unquoted): a raw key as a blob literal. Hex only, nothing to escape.
  """
  @spec pragma(binary()) :: String.t()
  def pragma(<<_::binary-size(@bytes)>> = key),
    do: "\"x'" <> Base.encode16(key, case: :lower) <> "'\""

  @doc "Recovery code: Base32, groups of four, separated by dashes."
  @spec code(binary()) :: String.t()
  def code(<<_::binary-size(@bytes)>> = key) do
    key
    |> Base.encode32(padding: false)
    |> String.graphemes()
    |> Enum.chunk_every(4)
    |> Enum.map_join("-", &Enum.join/1)
  end

  @doc "Key from a recovery code; ignores case, spaces and dashes."
  @spec aus_code(String.t()) :: {:ok, binary()} | {:error, :falscher_code}
  def aus_code(text) do
    normalized = text |> String.upcase() |> String.replace(~r/[^A-Z2-7]/, "")

    case Base.decode32(normalized, padding: false) do
      {:ok, <<_::binary-size(@bytes)>> = key} -> {:ok, key}
      _ -> {:error, :falscher_code}
    end
  end

  @doc "Seal `key` and store it under `home` (0600, replaces an existing seal)."
  @spec versiegeln(binary(), String.t(), SealedEnvelope.provider()) :: :ok | {:error, error()}
  def versiegeln(<<_::binary-size(@bytes)>> = key, home, provider) do
    case SealedEnvelope.seal(key, provider) do
      {:ok, envelope} -> Ort.schreiben!(Ort.schluessel(home), envelope <> "\n")
      {:error, reason} -> {:error, {:tresor, unwrap(reason)}}
    end
  end

  @doc "Open the sealed key; with the Tresor provider this asks for Touch ID."
  @spec oeffnen(String.t(), SealedEnvelope.provider()) :: {:ok, binary()} | {:error, error()}
  def oeffnen(home, provider) do
    with {:ok, text} <- lesen(home) do
      case SealedEnvelope.open(String.trim(text), provider) do
        {:ok, <<_::binary-size(@bytes)>> = key} -> {:ok, key}
        {:ok, _other} -> {:error, {:tresor, :invalid}}
        {:error, reason} -> {:error, {:tresor, unwrap(reason)}}
      end
    end
  end

  defp lesen(home) do
    case File.read(Ort.schluessel(home)) do
      {:ok, text} -> {:ok, text}
      {:error, _} -> {:error, :nicht_eingerichtet}
    end
  end

  @doc """
  Does `key` open the database at `path`? A database that does not exist
  yet fits every key (SQLCipher creates it with the first one).
  """
  @spec pruefen(binary(), String.t()) :: :ok | {:error, :falscher_schluessel}
  def pruefen(key, path) do
    if File.exists?(path), do: lesbar(key, path), else: :ok
  end

  defp lesbar(key, path) do
    {:ok, conn} = Exqlite.Sqlite3.open(path, mode: :readonly)

    try do
      with :ok <- Exqlite.Sqlite3.execute(conn, "PRAGMA key = " <> pragma(key)),
           :ok <- Exqlite.Sqlite3.execute(conn, "SELECT count(*) FROM sqlite_master") do
        :ok
      else
        _ -> {:error, :falscher_schluessel}
      end
    after
      Exqlite.Sqlite3.close(conn)
    end
  end

  defp unwrap({:key_agreement, reason}), do: reason
  defp unwrap(_format), do: :invalid

  @doc "Error as text for people, without a value."
  @spec beschreiben(error()) :: String.t()
  def beschreiben(:nicht_eingerichtet), do: "noch nicht eingerichtet: ratsprojekte einrichten"

  def beschreiben(:schon_eingerichtet),
    do: "schon eingerichtet; ein verlorenes Siegel ersetzt ratsprojekte recover"

  def beschreiben(:falscher_code), do: "Wiederherstellungscode hat nicht die erwartete Form"
  def beschreiben(:falscher_schluessel), do: "der Schlüssel passt nicht zur Datenbank"
  def beschreiben({:tresor, reason}), do: Ratsprojekte.Tresor.beschreiben(reason)
end
