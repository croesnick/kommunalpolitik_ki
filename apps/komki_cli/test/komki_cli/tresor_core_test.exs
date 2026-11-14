defmodule KomkiCli.Tresor.CoreTest do
  @moduledoc """
  Programmsuche des Tresor-Kerns: priv-Verzeichnis einer App, sonst PATH.
  Nicht async, weil die Tests PATH und den Code-Pfad veraendern.
  """

  use ExUnit.Case, async: false

  alias KomkiCli.{TestSupport, Tresor.Core}

  setup do
    path = System.get_env("PATH")
    on_exit(fn -> System.put_env("PATH", path) end)
    System.put_env("PATH", TestSupport.tmp_area!("leer"))
    :ok
  end

  defp program!(dir) do
    File.mkdir_p!(dir)
    path = Path.join(dir, "komki-tresor")
    File.write!(path, "#!/bin/sh\n")
    File.chmod!(path, 0o755)
    path
  end

  # Fake-App: ein ebin-Verzeichnis im Code-Pfad genuegt :code.priv_dir/1.
  defp fake_app!(app) do
    root = Path.join(TestSupport.tmp_area!("app"), Atom.to_string(app))
    ebin = Path.join(root, "ebin")
    File.mkdir_p!(ebin)
    Code.prepend_path(ebin)
    on_exit(fn -> Code.delete_path(ebin) end)
    root
  end

  test "das Programm im priv-Verzeichnis der App gewinnt vor PATH" do
    priv = program!(Path.join(fake_app!(:tresor_core_priv), "priv"))
    program!(System.get_env("PATH"))

    assert Core.binary(:tresor_core_priv) == priv
  end

  test "ohne priv-Programm gilt PATH" do
    fake_app!(:tresor_core_ohne)
    in_path = program!(System.get_env("PATH"))

    assert Core.binary(:tresor_core_ohne) == in_path
    assert Core.binary(:gibt_es_nicht) == in_path
    assert Core.binary(nil) == in_path
  end

  test "nirgends gefunden ergibt nil" do
    assert Core.binary(:gibt_es_nicht) == nil
  end
end
