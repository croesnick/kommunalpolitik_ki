defmodule KomkiCli.GoWatcher do
  @moduledoc """
  GO in der Session (Ticket #98): laeuft im Pane-BEAM neben pi, also
  ausserhalb der pi-Sandbox, und bringt GO-Anfragen des Vermittlers als
  tmux-Popup mit `komki go` vor die nutzende Person.

  Solange ein Terminal an der Session haengt, erneuert der Watcher jede
  Sekunde den Herzschlag `<base>/mediator/go/listener`. Nur dann wartet
  der Vermittler bei einer gesperrten Ausgabe auf ein GO
  (`KomkiMediator.Go.listening?/1`); ohne Zuhoerer, etwa bei `komki run`
  oder einer abgedockten Session, lehnt er sofort ab wie bisher.
  """

  alias KomkiMediator.Go

  @interval_ms 1_000

  @doc """
  Startet den Watcher als verlinkten Prozess. `tmux` ist die
  tmux-Grundzeile (`[bin, "-L", server]`), `komki` der Pfad des
  komki-Programms.
  """
  @spec start_link(Path.t(), [String.t()], String.t()) :: pid()
  def start_link(base, [_bin | _] = tmux, komki) do
    dir = Path.join([base, "mediator", "go"])
    spawn_link(fn -> loop(%{base: base, dir: dir, tmux: tmux, komki: komki}, []) end)
  end

  defp loop(state, shown) do
    shown =
      if attached?(state.tmux) do
        File.mkdir_p!(state.dir)
        File.touch!(Go.listener_path(state.dir))
        popup_new(state, shown)
      else
        shown
      end

    Process.sleep(@interval_ms)
    loop(state, shown)
  end

  # Jede Anfrage (Call-Hash) bekommt hoechstens ein Popup; `komki go`
  # darin beantwortet alle offenen.
  defp popup_new(state, shown) do
    hashes = state.dir |> Go.pending() |> Enum.map(& &1["call_hash"])

    if Enum.any?(hashes, &(&1 not in shown)), do: popup(state)
    hashes
  end

  defp popup(%{tmux: [bin | args], base: base, komki: komki}) do
    command = Enum.map_join([komki, "go"], " ", &sh_quote/1)

    System.cmd(
      bin,
      args ++
        ["display-popup", "-t", "komki", "-E", "-w", "90%", "-h", "60%"] ++
        ["-T", " GO-Anfrage ", "-e", "KOMKI_HOME=" <> base, command <> "; sleep 2"],
      stderr_to_stdout: true
    )
  end

  defp attached?([bin | args]) do
    case System.cmd(bin, args ++ ["list-clients", "-t", "komki"], stderr_to_stdout: true) do
      {out, 0} -> String.trim(out) != ""
      _ -> false
    end
  end

  defp sh_quote(word), do: "'" <> String.replace(word, "'", "'\\''") <> "'"
end
