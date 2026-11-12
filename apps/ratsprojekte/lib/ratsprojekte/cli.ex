defmodule Ratsprojekte.CLI do
  @moduledoc """
  The `ratsprojekte` command (ADR 0004, #440). `make ratsprojekte` links
  `rel/overlays/bin/ratsprojekte-befehl` as `ratsprojekte`; it runs here via
  `bin/ratsprojekte eval` in a VM of its own, without starting the hub.

      ratsprojekte einrichten        key, seal, recovery code (once)
      ratsprojekte launchagent an    start at login, locked
      ratsprojekte launchagent aus
      ratsprojekte open              Touch ID, then the browser with a one-time link
      ratsprojekte sperren | status
      ratsprojekte connector-token   SHA-256 of komki's token from stdin
      ratsprojekte recover           seal the key again from the recovery code

  `run/3` returns `{text, exit code}`; `main/1` prints and halts.
  """

  alias Ratsprojekte.{LaunchAgent, Ort, Schluessel}

  @usage """
  Aufruf: ratsprojekte einrichten | open | sperren | status | recover
                       | connector-token | launchagent an|aus
  """

  @spec main([String.t()]) :: no_return()
  def main(argv) do
    {text, code} = run(argv, Ort.home(), provider())
    IO.write(text)
    System.halt(code)
  end

  @doc false
  def provider, do: {Ratsprojekte.Tresor, reason: "ratsprojekte entsperren"}

  @spec run([String.t()], String.t(), SealedEnvelope.provider(), keyword()) ::
          {String.t(), non_neg_integer()}
  def run(argv, home, provider, io \\ [])

  def run(["einrichten"], home, provider, _io) do
    cond do
      File.exists?(Ort.schluessel(home)) ->
        fehler(Schluessel.beschreiben(:schon_eingerichtet))

      File.exists?(Ort.datenbank(home)) ->
        fehler(
          "hier liegt schon eine Datenbank; ihren Schlüssel holt ratsprojekte recover zurück"
        )

      true ->
        Ort.anlegen!(home)
        key = Schluessel.neu()

        case Schluessel.versiegeln(key, home, provider) do
          :ok -> {eingerichtet(key), 0}
          {:error, reason} -> fehler(Schluessel.beschreiben(reason))
        end
    end
  end

  def run(["open"], home, _provider, io) do
    case verwaltung(home, "oeffnen") do
      {:ok, link} ->
        oeffnen = Keyword.get(io, :browser, &System.cmd("/usr/bin/open", [&1]))
        oeffnen.(link)
        {"Hub entsperrt, der Browser öffnet die Oberfläche.\n", 0}

      {:error, text} ->
        fehler(text)
    end
  end

  def run(["sperren"], home, _provider, _io),
    do: einfach(verwaltung(home, "sperren"), "Hub gesperrt.")

  def run(["status"], home, _provider, _io) do
    case verwaltung(home, "status") do
      {:ok, status} -> {"Hub läuft, " <> status <> ".\n", 0}
      {:error, text} -> fehler(text)
    end
  end

  def run(["connector-token"], home, _provider, io) do
    line = io |> Keyword.get(:gets, &IO.gets/1) |> then(& &1.("")) |> to_string() |> String.trim()

    if line =~ ~r/\A[0-9a-f]{64}\z/ do
      Ort.anlegen!(home)
      Ort.schreiben!(Ort.token_hash(home), line <> "\n")
      {"Connector-Token hinterlegt (nur sein Hash).\n", 0}
    else
      fehler(
        "erwartet eine Zeile mit dem SHA-256 (hex), etwa: komki secret erzeugen ratsprojekte-hub | ratsprojekte connector-token"
      )
    end
  end

  def run(["recover"], home, provider, io) do
    gets = Keyword.get(io, :gets, &IO.gets/1)
    db = Ort.datenbank(home)

    with true <-
           File.exists?(db) ||
             {:error, "keine Datenbank: erst ratsprojekte.db aus Time Machine zurückholen"},
         {:ok, key} <- Schluessel.aus_code(to_string(gets.("Wiederherstellungscode: "))),
         :ok <- Schluessel.pruefen(key, db),
         :ok <- Schluessel.versiegeln(key, home, provider) do
      {"""
       Schlüssel neu versiegelt. Der Connector braucht einen neuen Token:
         komki secret erzeugen ratsprojekte-hub | ratsprojekte connector-token
       """, 0}
    else
      {:error, text} when is_binary(text) -> fehler(text)
      {:error, reason} -> fehler(Schluessel.beschreiben(reason))
    end
  end

  def run(["launchagent", "an"], home, _provider, io) do
    root = Keyword.get(io, :root, System.get_env("RELEASE_ROOT"))
    env = [{"PHX_SERVER", "true"}, {"HOME", System.user_home!()}, {"RATSPROJEKTE_HOME", home}]

    case LaunchAgent.an(root, env) do
      :ok ->
        {"LaunchAgent geladen: Der Hub startet bei der Anmeldung gesperrt. Öffnen mit: ratsprojekte open\n",
         0}

      {:error, text} ->
        fehler(text)
    end
  end

  def run(["launchagent", "aus"], _home, _provider, _io),
    do: einfach(LaunchAgent.aus(), "LaunchAgent entfernt.")

  def run(_argv, _home, _provider, _io), do: {@usage, 2}

  defp eingerichtet(key) do
    """
    Eingerichtet. Der Schlüssel der Datenbank ist mit der Secure Enclave dieses
    Macs versiegelt.

    Wiederherstellungscode (wird nur jetzt gezeigt, gehört in den Passwortmanager):

      #{Schluessel.code(key)}

    Ohne ihn ist eine Sicherung nach einem Ausfall des Rechners wertlos.
    Weiter: ratsprojekte launchagent an, dann ratsprojekte open
    """
  end

  defp einfach(:ok, text), do: {text <> "\n", 0}
  defp einfach({:ok, _}, text), do: {text <> "\n", 0}
  defp einfach({:error, text}, _text), do: fehler(text)

  defp fehler(text), do: {"ratsprojekte: " <> text <> "\n", 1}

  # One line to the hub's socket, one line back. Touch ID may take up to two
  # minutes, hence the long receive timeout.
  defp verwaltung(home, befehl) do
    if Ort.passt?(home),
      do: verbinden(home, befehl),
      else: {:error, "RATSPROJEKTE_HOME ist zu lang für die Sockets"}
  end

  defp verbinden(home, befehl) do
    case :gen_tcp.connect(
           {:local, Ort.verwaltung(home)},
           0,
           [:binary, packet: :line, active: false],
           2_000
         ) do
      {:ok, sock} ->
        :ok = :gen_tcp.send(sock, befehl <> "\n")
        result = :gen_tcp.recv(sock, 0, 150_000)
        :gen_tcp.close(sock)

        case result do
          {:ok, "ok" <> rest} -> {:ok, String.trim(rest)}
          {:ok, "fehler " <> text} -> {:error, String.trim(text)}
          _ -> {:error, "keine Antwort vom Hub"}
        end

      {:error, _} ->
        {:error,
         "der Hub läuft nicht (ratsprojekte launchagent an, Log: ~/Library/Logs/ratsprojekte/hub.log)"}
    end
  end
end
