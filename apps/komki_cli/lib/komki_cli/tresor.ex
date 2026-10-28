defmodule KomkiCli.Tresor do
  @moduledoc """
  Geheimnisse mit der Secure Enclave versiegeln und oeffnen — Adapter auf
  `KomkiCli.Tresor.Core` (Ticket #224): Der Kern (Ports, Exit-Codes,
  Siegel-Form) ist komki-frei und soll spaeter als eigenstaendiges Paket
  herausgezogen werden. Hier wohnt die komki-Seite: die Programmsuche neben
  dem laufenden komki (Quellbaum, Homebrew `libexec`, Burrito `dist/`) und
  die Application-Env `:komki_cli, :tresor` (Tests).

  Der Schluesselbund enthaelt danach nur noch das Siegel. Oeffnen geht nur
  ueber die Secure Enclave dieses Macs und nur mit Touch ID oder dem
  Passwort des Macs. Das gilt fuer jeden Prozess, der den Eintrag liest,
  nicht nur fuer komki. Erlang erreicht die Secure Enclave nicht selbst,
  deshalb das eigene Programm (AGENTS.md, Elixir-first, Ausnahme).
  """

  alias KomkiCli.Tresor.Core

  @type error :: Core.error()

  @doc """
  `komki-tresor` neben dem laufenden komki (Homebrew: `libexec`, Quellbaum:
  `apps/komki_cli`), sonst im PATH (kanonisch, fuer die Seatbelt-Pfadform),
  sonst das mitgebaute Programm aus dem priv-Verzeichnis (Kern). nil, wenn
  es nirgends liegt. Die Application-Env `:komki_cli, :tresor` gewinnt
  (Tests).
  """
  @spec binary() :: String.t() | nil
  def binary do
    Application.get_env(:komki_cli, :tresor) || discover()
  end

  # komki-Kopplung lebt nur hier: neben dem laufenden komki, sonst PATH,
  # sonst der Kern (priv-Verzeichnis).
  defp discover do
    beside =
      case KomkiCli.Config.self_komki() do
        nil -> nil
        komki -> Path.join(Path.dirname(komki), "komki-tresor")
      end

    cond do
      beside && File.exists?(beside) -> beside
      path = System.find_executable("komki-tresor") -> KomkiCli.Config.canonical(path)
      true -> Core.binary()
    end
  end

  @doc "Ist `text` ein Siegel (und kein Klartext)?"
  @spec sealed?(String.t()) :: boolean()
  def sealed?(text), do: Core.sealed?(text)

  @doc """
  Ist das Siegel vollstaendig (Base64, JSON mit `key`, `eph`, `box`)?
  Prueft nur die Form, oeffnet nichts. Ein gekuerztes Siegel faellt durch.
  """
  @spec well_formed?(String.t()) :: boolean()
  def well_formed?(text), do: Core.well_formed?(text)

  @doc "Klartext versiegeln. Keine Rueckfrage: Versiegeln braucht nur den oeffentlichen Schluessel."
  @spec seal(String.t(), keyword()) :: {:ok, String.t()} | {:error, error()}
  def seal(value, opts \\ []) when is_binary(value), do: Core.seal(value, inject(opts))

  @doc "Siegel oeffnen; macOS fragt mit `reason` nach Touch ID oder Passwort."
  @spec open(String.t(), String.t(), keyword()) :: {:ok, String.t()} | {:error, error()}
  def open(sealed, reason, opts \\ []) when is_binary(sealed) and is_binary(reason),
    do: Core.open(sealed, reason, inject(opts))

  @doc "Fehler als Text ohne Wert."
  @spec describe(error()) :: String.t()
  def describe(error), do: Core.describe(error)

  # Explizites opts[:command] (Tests) gewinnt; sonst einmal hier aufloesen.
  # nil (nirgends gefunden) bleibt nil: der Kern meldet dann :missing_bin.
  defp inject(opts) do
    if Keyword.has_key?(opts, :command), do: opts, else: Keyword.put(opts, :command, binary())
  end
end
