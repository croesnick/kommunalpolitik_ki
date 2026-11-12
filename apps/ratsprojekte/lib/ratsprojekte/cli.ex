defmodule Ratsprojekte.CLI do
  @moduledoc """
  The `ratsprojekte` command (ADR 0004, #440). `make ratsprojekte` links
  `rel/overlays/bin/ratsprojekte-befehl` as `ratsprojekte`; it runs here via
  `bin/ratsprojekte eval` in a VM of its own, without starting the hub.

      ratsprojekte einrichten        key, seal, recovery code (once), LaunchAgent
      ratsprojekte launchagent an    (re)load the LaunchAgent: start at login, locked
      ratsprojekte launchagent aus
      ratsprojekte open              Touch ID, then the browser with a one-time link
                                     (the lock page in the browser offers the same)
      ratsprojekte sperren | status
      ratsprojekte connector-token   SHA-256 of komki's token from stdin
      ratsprojekte recover           seal the key again from the recovery code

  `run/4` returns `{text, exit code}`; `main/1` prints and halts. `io`
  replaces the outside world in tests (`:browser`, `:gets`, `:launchagent`).
  """

  alias Ratsprojekte.{LaunchAgent, Ort, Schluessel}

  @adresse "http://localhost:4100"

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

  def run(["einrichten"], home, provider, io) do
    cond do
      File.exists?(Ort.schluessel(home)) ->
        fehler(Schluessel.beschreiben(:schon_eingerichtet))

      File.exists?(Ort.datenbank(home)) ->
        fehler(
          "hier liegt schon eine Datenbank; ihren Schlüssel holt ratsprojekte recover zurück"
        )

      true ->
        einrichten(home, provider, io)
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
    line =
      case io |> Keyword.get(:gets, &IO.gets/1) |> then(& &1.("")) do
        text when is_binary(text) -> String.trim(text)
        _eof -> ""
      end

    cond do
      line =~ ~r/\A[0-9a-f]{64}\z/ ->
        Ort.anlegen!(home)
        Ort.schreiben!(Ort.token_hash(home), line <> "\n")
        {"Connector-Token hinterlegt (nur sein Hash).\n", 0}

      # The usual cause: the komki in PATH does not know `secret erzeugen` yet
      # and wrote its error to stderr only.
      line == "" ->
        fehler(
          "nichts auf stdin erhalten; lief komki secret erzeugen ratsprojekte-hub ohne Fehler? (komki --version, eine ältere Version kennt den Befehl nicht)"
        )

      true ->
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
    case Keyword.get(io, :launchagent, &launchagent_an/1).(home) do
      :ok -> {"Der Hub läuft gesperrt und startet bei jeder Anmeldung.\n" <> oeffnen_hinweis(), 0}
      {:error, text} -> fehler(text)
    end
  end

  def run(["launchagent", "aus"], _home, _provider, _io),
    do: einfach(LaunchAgent.aus(), "LaunchAgent entfernt.")

  def run(_argv, _home, _provider, _io), do: {@usage, 2}

  defp launchagent_an(home) do
    env = [{"PHX_SERVER", "true"}, {"HOME", System.user_home!()}, {"RATSPROJEKTE_HOME", home}]

    case System.get_env("RELEASE_ROOT") do
      nil -> {:error, "nur aus dem Release aufrufbar (make ratsprojekte)"}
      root -> with :ok <- LaunchAgent.an(root, env), do: warten(home, 20_000)
    end
  end

  defp einrichten(home, provider, io) do
    Ort.anlegen!(home)
    key = Schluessel.neu()

    case Schluessel.versiegeln(key, home, provider) do
      # The code is shown even if the LaunchAgent fails: it exists only now.
      :ok -> starten(eingerichtet(key), home, io)
      {:error, reason} -> fehler(Schluessel.beschreiben(reason))
    end
  end

  defp starten(text, home, io) do
    case Keyword.get(io, :launchagent, &launchagent_an/1).(home) do
      :ok -> {text <> weiter(), 0}
      {:error, fehler} -> {text <> "ratsprojekte: " <> fehler <> "\n", 1}
    end
  end

  # launchd returns before the BEAM is up; wait until the hub answers, so
  # `ratsprojekte open` right after this command finds it.
  defp warten(home, ms) when ms <= 0 do
    case verwaltung(home, "status") do
      {:ok, _} ->
        :ok

      {:error, _} ->
        {:error,
         "LaunchAgent geladen, aber der Hub antwortet nicht (Log: ~/Library/Logs/ratsprojekte/hub.log)"}
    end
  end

  defp warten(home, ms) do
    case verwaltung(home, "status") do
      {:ok, _} ->
        :ok

      {:error, _} ->
        Process.sleep(250)
        warten(home, ms - 250)
    end
  end

  defp eingerichtet(key) do
    """
    Eingerichtet. Der Schlüssel der Datenbank ist mit der Secure Enclave dieses
    Macs versiegelt.

    Wiederherstellungscode (wird nur jetzt gezeigt, gehört in den Passwortmanager):

      #{Schluessel.code(key)}

    Ohne ihn ist eine Sicherung nach einem Ausfall des Rechners wertlos.

    """
  end

  defp weiter do
    """
    Der Hub läuft gesperrt und startet bei jeder Anmeldung.

    Den Connector für komki anschließen:
      komki secret erzeugen ratsprojekte-hub | ratsprojekte connector-token

    """ <> oeffnen_hinweis()
  end

  defp oeffnen_hinweis do
    "Öffnen: #{@adresse} im Browser (als Lesezeichen), „Entsperren“, Touch ID.\n"
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
