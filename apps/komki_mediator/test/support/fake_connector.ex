defmodule KomkiMediator.FakeConnector do
  @moduledoc false

  # Fake-Connectoren fuer die Tests: echter KomkiConnector.Server auf einem
  # Unix-Socket in einem kurzen /tmp-Pfad (macOS-Grenze 103 Byte). Jeder
  # Aufruf meldet sich beim Test-Prozess mit Operation, Parametern, Kontext
  # und der Anzahl der Journal-Datensaetze zum Aufrufzeitpunkt; die Antwort
  # liefert die im Test gesetzte Funktion `reply.(op, params, context)`.

  alias KomkiConnector.Server

  @doc "Kurzes, frisches Connector-Verzeichnis unter /tmp."
  def short_dir do
    dir = "/tmp/km" <> Base.encode16(:crypto.strong_rand_bytes(4), case: :lower)
    File.mkdir_p!(dir)
    dir
  end

  @doc """
  Startet den Fake fuer Connector `id` unter `dir/<id>.sock`. Der
  Listener haengt am aufrufenden Prozess (Test) und endet mit ihm.
  """
  def start(id, dir, journal_path, reply) do
    module = module(id)
    path = Path.join(dir, id <> ".sock")
    {:ok, listener} = Server.listen(path)
    state = %{test: self(), journal_path: journal_path, reply: reply}
    pid = spawn_link(fn -> Server.accept_loop(listener, module, state) end)
    :ok = :gen_tcp.controlling_process(listener, pid)
    pid
  end

  defp module("ris"), do: KomkiMediator.FakeConnector.Ris
  defp module("web"), do: KomkiMediator.FakeConnector.Web
  defp module("vault"), do: KomkiMediator.FakeConnector.Vault

  @doc false
  def handle_op(id, op, params, context, state) do
    records = length(KomkiMediator.TestHelpers.journal_records(state.journal_path))
    send(state.test, {:connector_called, id, op, params, context, records})
    state.reply.(op, params, context)
  end

  defmodule Ris do
    @moduledoc false
    @behaviour KomkiConnector.Server
    def manifest_id, do: "ris"
    def init(arg), do: {:ok, arg}

    def handle_op(op, params, context, state),
      do: KomkiMediator.FakeConnector.handle_op("ris", op, params, context, state)
  end

  defmodule Web do
    @moduledoc false
    @behaviour KomkiConnector.Server
    def manifest_id, do: "web"
    def init(arg), do: {:ok, arg}

    def handle_op(op, params, context, state),
      do: KomkiMediator.FakeConnector.handle_op("web", op, params, context, state)
  end

  defmodule Vault do
    @moduledoc false
    @behaviour KomkiConnector.Server
    def manifest_id, do: "vault"
    def init(arg), do: {:ok, arg}

    def handle_op(op, params, context, state),
      do: KomkiMediator.FakeConnector.handle_op("vault", op, params, context, state)
  end
end
