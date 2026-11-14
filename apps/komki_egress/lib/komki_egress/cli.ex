defmodule KomkiEgress.CLI do
  @moduledoc """
  Escript-Einstiegspunkt `komki-egress`.

      echo '{"ports": {"49601": {"connector": "web", "allow": ["api.search.brave.com:443"]}}}' \\
        | komki-egress

  Liest genau eine JSON-Zeile von stdin (Format: `KomkiEgress.Config`),
  bindet je Eintrag `127.0.0.1:<port>` und schreibt danach eine
  Startnotiz als JSON-Zeile auf stdout. Ungültige Konfiguration oder ein
  belegter Port: Meldung auf stderr, Exit 2. Argumente gibt es nicht
  (außer `--help`); die Test-Optionen von `KomkiEgress.start/2` sind
  bewusst nicht von außen erreichbar.
  """

  @usage """
  komki-egress < config.json

  stdin: eine JSON-Zeile
    {"ports": {"<port>": {"connector": "<name>", "allow": ["host:port", ...]}}}
  """

  def main(["--help"]), do: IO.puts(@usage)

  def main([]) do
    case start(IO.read(:stdio, :line)) do
      {:ok, ports} ->
        IO.puts(JSON.encode!(%{"komki_egress" => "listening", "ports" => ports}))
        Process.sleep(:infinity)

      {:error, message} ->
        fail(message)
    end
  end

  def main(_argv), do: fail("keine Argumente erwartet; Konfiguration kommt per stdin\n" <> @usage)

  @doc "Parst die stdin-Zeile und startet die Listener; gibt die Ports zurück."
  @spec start(term(), keyword()) :: {:ok, [pos_integer()]} | {:error, String.t()}
  def start(line, opts \\ [])

  def start(line, opts) when is_binary(line) do
    with {:ok, config} <- KomkiEgress.Config.parse(line),
         {:ok, _pids} <- KomkiEgress.start(config, opts) do
      {:ok, config |> Map.keys() |> Enum.sort()}
    end
  end

  def start(_eof, _opts), do: {:error, "keine Konfiguration auf stdin (erwartet eine JSON-Zeile)"}

  # Beide Pfade kehren nicht zurück (sleep bzw. halt), für dialyzer vermerkt.
  @dialyzer {:nowarn_function, main: 1, fail: 1}
  defp fail(message) do
    IO.puts(:stderr, "komki-egress: " <> message)
    System.halt(2)
  end
end
