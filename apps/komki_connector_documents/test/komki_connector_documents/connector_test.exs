defmodule KomkiConnectorDocuments.ConnectorTest do
  use ExUnit.Case, async: true

  alias KomkiConnector.{Client, Server}

  setup do
    root = Path.join(System.tmp_dir!(), "kcd-#{System.unique_integer([:positive])}")
    dir = Path.join(root, "documents")
    File.mkdir_p!(dir)
    File.write!(Path.join(dir, "doc-oeffentlich.md"), "# Oeffentliche Notiz\n")
    File.write!(Path.join(root, "geheim.md"), "geheim\n")
    File.ln_s!(Path.join(root, "geheim.md"), Path.join(dir, "doc-link.md"))

    # Kurzer Socket-Pfad: macOS begrenzt Unix-Socket-Pfade auf 103 Byte.
    socket = "/tmp/kcd-" <> Integer.to_string(System.unique_integer([:positive])) <> ".sock"
    {:ok, state} = KomkiConnectorDocuments.init(dir)
    {:ok, listener} = Server.listen(socket)
    pid = spawn(fn -> Server.accept_loop(listener, KomkiConnectorDocuments, state) end)
    _ = :gen_tcp.controlling_process(listener, pid)

    on_exit(fn ->
      Process.exit(pid, :kill)
      File.rm(socket)
      File.rm_rf!(root)
    end)

    %{socket: socket}
  end

  test "liest ein Raumdokument", %{socket: socket} do
    assert {:ok, %{"document_id" => "doc-oeffentlich", "content" => "# Oeffentliche Notiz\n"}} =
             Client.call(socket, "c1", "read", %{"document_id" => "doc-oeffentlich"})
  end

  test "fehlendes Dokument: not-found", %{socket: socket} do
    assert {:error, %{"code" => "not-found"}} =
             Client.call(socket, "c2", "read", %{"document_id" => "doc-phantom"})
  end

  test "Symlink wird nicht verfolgt: forbidden-path", %{socket: socket} do
    assert {:error, %{"code" => "forbidden-path"}} =
             Client.call(socket, "c3", "read", %{"document_id" => "doc-link"})
  end

  test "Pfade scheitern am Manifest-Pattern", %{socket: socket} do
    for id <- ["../geheim", "/etc/passwd", "Doc", "doc.md"] do
      assert {:error, %{"code" => "bad-request"}} =
               Client.call(socket, "c4", "read", %{"document_id" => id})
    end
  end

  test "ping meldet die Fassung", %{socket: socket} do
    assert {:ok, %{"fassung" => "komki-documents/1", "ops" => ["read"]}} =
             Client.call(socket, "c5", "ping", %{})
  end
end
