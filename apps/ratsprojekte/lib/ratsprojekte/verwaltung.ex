defmodule Ratsprojekte.Verwaltung do
  @moduledoc """
  The socket of the `ratsprojekte` command (`Ort.verwaltung/1`, mode 0600):
  one line in, one line out, one connection at a time.

      oeffnen   ->  ok <link>     Touch ID, then a one-time link
      sperren   ->  ok
      status    ->  ok offen | ok gesperrt
      otherwise ->  fehler <text without values>

  The hub asks for Touch ID itself (`Sperre.oeffnen/1`); the key never
  leaves the hub process. The release runs without Erlang distribution, so
  this socket is the only way in besides the browser port and the connector
  socket.
  """

  use Task, restart: :permanent

  alias Ratsprojekte.{Schluessel, Sperre}

  @max_line 64

  @spec start_link(keyword()) :: {:ok, pid()}
  def start_link(opts) do
    pfad = Keyword.fetch!(opts, :pfad)
    sperre = Keyword.get(opts, :sperre, Sperre)
    # The endpoint's URL is known only once it runs; resolve it per request.
    basis_url = Keyword.get(opts, :basis_url, &RatsprojekteWeb.Endpoint.url/0)
    listen = lauschen(pfad)

    # Listening before start_link returns: the socket exists once the hub
    # counts as started. The task then owns it and closes it with itself.
    {:ok, pid} =
      Task.start_link(fn ->
        receive do
          :uebernommen -> annehmen(listen, sperre, basis_url)
        end
      end)

    :ok = :gen_tcp.controlling_process(listen, pid)
    send(pid, :uebernommen)
    {:ok, pid}
  end

  defp lauschen(pfad) do
    _ = File.rm(pfad)

    {:ok, listen} =
      :gen_tcp.listen(0, [
        :binary,
        ifaddr: {:local, pfad},
        packet: :line,
        active: false,
        buffer: @max_line
      ])

    File.chmod!(pfad, 0o600)
    listen
  end

  defp annehmen(listen, sperre, basis_url) do
    {:ok, sock} = :gen_tcp.accept(listen)

    with {:ok, line} <- :gen_tcp.recv(sock, 0, 5_000) do
      :gen_tcp.send(sock, antwort(String.trim(line), sperre, basis_url) <> "\n")
    end

    :gen_tcp.close(sock)
    annehmen(listen, sperre, basis_url)
  end

  @doc false
  def antwort("oeffnen", sperre, basis_url) do
    case Sperre.oeffnen(sperre) do
      {:ok, token} -> "ok " <> basis_url.() <> "/zugang/" <> token
      {:error, :datenbank} -> "fehler Datenbank nicht zu öffnen, Log prüfen"
      {:error, reason} -> "fehler " <> Schluessel.beschreiben(reason)
    end
  end

  def antwort("sperren", sperre, _basis_url) do
    :ok = Sperre.sperren(sperre)
    "ok"
  end

  def antwort("status", sperre, _basis_url), do: "ok " <> Atom.to_string(Sperre.status(sperre))
  def antwort(_other, _sperre, _basis_url), do: "fehler unbekannter Befehl"
end
