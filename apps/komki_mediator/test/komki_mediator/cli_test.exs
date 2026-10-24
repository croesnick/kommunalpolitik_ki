defmodule KomkiMediator.CLITest do
  # Ticket #143: Ohne gueltige Token-Datei startet der Vermittler nicht.
  use ExUnit.Case, async: true

  alias KomkiMediator.{CLI, TestHelpers}

  setup do
    dir = TestHelpers.tmp_base("komki-mediator-cli-")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    %{path: Path.join(dir, "mediator.token")}
  end

  test "fehlende Token-Datei: Start verweigert", %{path: path} do
    assert {:error, %{"error" => "token", "detail" => detail}} = CLI.load_token(path)
    assert detail =~ path
  end

  test "ungueltiger Inhalt: Start verweigert, der Fehler nennt den Inhalt nicht", %{path: path} do
    for content <- ["zu-kurz", String.duplicate("G", 64), String.duplicate("a", 63)] do
      File.write!(path, content)
      assert {:error, %{"error" => "token", "detail" => detail}} = CLI.load_token(path)
      refute detail =~ content
    end

    File.write!(path, "")
    assert {:error, %{"error" => "token"}} = CLI.load_token(path)
  end

  test "64 Hex-Zeichen, optional mit Zeilenumbruch", %{path: path} do
    token = TestHelpers.new_token()
    File.write!(path, token)
    assert {:ok, ^token} = CLI.load_token(path)
    File.write!(path, token <> "\n")
    assert {:ok, ^token} = CLI.load_token(path)
  end
end
