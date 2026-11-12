defmodule WegwerfHub.CLI do
  @moduledoc """
  DURCHSTICH #409 (Wegwerf, nie gemergt): Einstieg des Wegwerf-Hubs.

      wegwerf-hub --dir <pfad> serve                  # Bandit auf <pfad>/hub.sock
      wegwerf-hub --dir <pfad> liste                  # Vorschläge und Verlauf
      wegwerf-hub --dir <pfad> entscheiden v-1 --teile 1,2
      wegwerf-hub --dir <pfad> ablehnen v-1
      wegwerf-hub --dir <pfad> gesperrt on|off
      wegwerf-hub --dir <pfad> leeren                 # für den Zwei-Welten-Vergleich
      wegwerf-hub --dir <pfad> stand-ausgeben         # <pfad>/stand.json (#419)

  `serve` verlangt die Datei `token-hash` im Hub-Verzeichnis (der
  Klartext liegt nur beim Connector; der Hub kennt den Hash, #415) und
  setzt die Rechte der Socket-Datei auf 0600. Die Verwaltungs-Befehle
  laufen gegen die Dateien und funktionieren neben dem laufenden
  Server.
  """

  alias WegwerfHub.Store

  @spec main([String.t()]) :: no_return()
  def main(argv) do
    case parse(argv) do
      {:ok, %{dir: dir, befehl: "serve"}} ->
        serve(dir)

      {:ok, %{dir: dir, befehl: "liste"}} ->
        liste(dir)

      {:ok, %{dir: dir, befehl: "entscheiden", id: id, teile: teile}} ->
        entscheiden(dir, id, teile)

      {:ok, %{dir: dir, befehl: "ablehnen", id: id}} ->
        ablehnen(dir, id)

      {:ok, %{dir: dir, befehl: "gesperrt", schalter: schalter}} ->
        gesperrt(dir, schalter)

      {:ok, %{dir: dir, befehl: "leeren"}} ->
        leeren(dir)

      {:ok, %{dir: dir, befehl: "stand-ausgeben"}} ->
        stand_ausgeben(dir)

      {:error, usage} ->
        fail(usage)
    end
  end

  defp parse([_]), do: {:error, usage()}

  defp parse(argv) do
    case OptionParser.parse(argv, strict: [dir: :string, teile: :string]) do
      {opts, ["serve" | _rest], []} ->
        with_dir(opts, %{befehl: "serve"})

      {opts, ["liste" | _rest], []} ->
        with_dir(opts, %{befehl: "liste"})

      {opts, ["leeren" | _rest], []} ->
        with_dir(opts, %{befehl: "leeren"})

      {opts, ["stand-ausgeben" | _rest], []} ->
        with_dir(opts, %{befehl: "stand-ausgeben"})

      {opts, ["entscheiden", id | _rest], []} ->
        with_dir(opts, %{befehl: "entscheiden", id: id, teile: teile(opts)})

      {opts, ["ablehnen", id | _rest], []} ->
        with_dir(opts, %{befehl: "ablehnen", id: id})

      {opts, ["gesperrt", schalter | _rest], []} ->
        with_dir(opts, %{befehl: "gesperrt", schalter: schalter})

      _ ->
        {:error, usage()}
    end
  end

  defp with_dir(opts, map) do
    case Keyword.fetch(opts, :dir) do
      {:ok, dir} when dir != "" -> {:ok, Map.put(map, :dir, dir)}
      _ -> {:error, "--dir fehlt\n\n" <> usage()}
    end
  end

  defp teile(opts) do
    case Keyword.get(opts, :teile) do
      nil -> []
      spec -> spec |> String.split(",") |> Enum.map(&String.to_integer/1)
    end
  end

  # -------------------------------------------------------------------------
  # serve
  # -------------------------------------------------------------------------

  defp serve(dir) do
    File.mkdir_p!(dir)

    unless File.exists?(Path.join(dir, "token-hash")) do
      fail("token-hash fehlt in #{dir} — der Hub kennt nur den Hash des Connector-Tokens (#415)")
    end

    socket = Path.join(dir, "hub.sock")
    _ = File.rm(socket)

    case Bandit.start_link(
           plug: {WegwerfHub.HTTP, dir: dir},
           scheme: :http,
           ip: {:local, socket},
           port: 0
         ) do
      {:ok, _pid} ->
        :ok = File.chmod(socket, 0o600)
        IO.puts("wegwerf-hub lauscht auf #{socket}")
        Process.sleep(:infinity)

      {:error, reason} ->
        fail("Start fehlgeschlagen: #{inspect(reason)}")
    end
  end

  # -------------------------------------------------------------------------
  # Verwaltung (Redaktion)
  # -------------------------------------------------------------------------

  defp liste(dir) do
    IO.puts("== Vorschläge ==")

    for proposal <- Store.vorschlaege(dir) do
      IO.puts("")
      IO.puts("#{proposal["id"]} [#{proposal["status"]}] #{proposal["titel"]}")

      IO.puts(
        "  Hinweis: " <>
          (proposal["projekt_hinweis"] || "ohne Zuordnung") <>
          " · Labels: " <> Enum.join(proposal["labels"], ", ")
      )

      proposal["teile"]
      |> Enum.with_index(1)
      |> Enum.each(fn {teil, index} -> zeige_teil(index, teil) end)
    end

    IO.puts("")
    IO.puts("== Verlauf ==")
    Enum.each(Store.verlauf(dir), &IO.puts("· " <> &1["text"]))
    IO.puts("")
    IO.puts("Connector-Anfragen: #{Store.anfragen(dir)}")
  end

  defp zeige_teil(index, teil) do
    IO.puts("  #{index}. [#{teil["pruefstatus"]}] #{teil["aussage"]}")

    IO.puts(
      "     Quelle: #{teil["quelle"]}" <>
        if(teil["fundstelle"], do: " · Fundstelle: #{teil["fundstelle"]}", else: "")
    )
  end

  defp entscheiden(dir, id, teile) do
    case Store.entscheiden(dir, id, teile) do
      :ok -> IO.puts("#{id}: #{length(teile)} Teil(e) übernommen, der Rest gelöscht")
      {:error, detail} -> fail(detail)
    end
  end

  defp ablehnen(dir, id) do
    case Store.ablehnen(dir, id) do
      :ok -> IO.puts("#{id}: abgelehnt, alle Teile gelöscht")
      {:error, detail} -> fail(detail)
    end
  end

  defp gesperrt(dir, "on") do
    File.touch(Path.join(dir, "gesperrt"))
    IO.puts("Hub gesperrt — der Connector bekommt „Hub gesperrt“, gepuffert wird nichts")
  end

  defp gesperrt(dir, "off") do
    File.rm(Path.join(dir, "gesperrt"))
    IO.puts("Hub entsperrt")
  end

  defp gesperrt(_dir, _schalter), do: fail("gesperrt on|off")

  defp leeren(dir) do
    :ok = Store.leeren(dir)
    IO.puts("Vorschläge geleert")
  end

  defp stand_ausgeben(dir) do
    {:ok, path} = Store.stand_ausgeben(dir)
    IO.puts("Stand ausgegeben: #{path}")
  end

  defp usage do
    """
    wegwerf-hub --dir <pfad> serve
    wegwerf-hub --dir <pfad> liste
    wegwerf-hub --dir <pfad> entscheiden <id> --teile 1,2
    wegwerf-hub --dir <pfad> ablehnen <id>
    wegwerf-hub --dir <pfad> gesperrt on|off
    wegwerf-hub --dir <pfad> leeren
    wegwerf-hub --dir <pfad> stand-ausgeben
    """
  end

  @spec fail(String.t()) :: no_return()
  defp fail(message) do
    IO.puts(:stderr, "wegwerf-hub: " <> message)
    System.halt(1)
  end
end
