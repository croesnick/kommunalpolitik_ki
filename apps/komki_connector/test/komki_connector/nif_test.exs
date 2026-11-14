defmodule KomkiConnector.NifTest do
  @moduledoc """
  Zweite Programmform (#288, CONTRACT.md §4): Kandidaten, Fundstelle und
  Bootstrap teilen eine Ordnung — Profil, Pin und Doctor beschreiben genau
  das Verzeichnis, aus dem der Connector wirklich lädt.
  """

  # Nicht async: die Bootstrap-Tests verändern den Code-Pfad der VM.
  use ExUnit.Case, async: false

  alias KomkiConnector.Nif

  # Kernel-kanonisch (macOS: /private/tmp/...): app_dirs gibt kanonische
  # Pfade zurueck, die Erwartungen muessen in derselben Form stehen.
  defp area!(prefix) do
    root = if(File.dir?("/tmp"), do: "/tmp", else: System.tmp_dir!())
    dir = Path.join([root, "nif-" <> prefix <> "-" <> suffix()])
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    Seatbelt.canonical(dir)
  end

  defp suffix, do: Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)

  defp place!(path) do
    File.mkdir_p!(path)
    path
  end

  test "app_dirs: Paket, Build-Baum und Nachbar-Build in Suchreihenfolge" do
    assert Nif.app_dirs("/opt/komki/libexec/komki", :ex_pdfium) == [
             "/opt/komki/libexec/lib/ex_pdfium",
             "/opt/komki/libexec/_build/dev/lib/ex_pdfium",
             "/opt/komki/_build/dev/lib/ex_pdfium"
           ]
  end

  test "app_dir: erste Fundstelle mit ebin gewinnt" do
    dir = area!("fundstelle")

    # Paket-Layout und Build-Baum nebeneinander; nur das Paket hat ein ebin.
    _pkg = place!(Path.join([dir, "pkg", "lib", "ex_pdfium", "ebin"]))
    place!(Path.join([dir, "pkg", "_build", "dev", "lib", "ex_pdfium"]))

    assert Nif.app_dir(Path.join([dir, "pkg", "komki"]), :ex_pdfium) ==
             Path.join([dir, "pkg", "lib", "ex_pdfium"])
  end

  test "app_dir: ein Verzeichnis ohne ebin zaehlt nicht" do
    dir = area!("ohne-ebin")
    place!(Path.join([dir, "lib", "ex_pdfium", "priv"]))

    assert Nif.app_dir(Path.join(dir, "komki"), :ex_pdfium) == nil
  end

  test "app_dir: ohne jede Fundstelle nil" do
    assert Nif.app_dir("/opt/komki-golden/bin/komki", :ex_pdfium) == nil
  end

  # make komki legt einen Symlink neben den Build-Baum (Muster exqlite,
  # Ticket #241): Die Kandidaten muessen auf der richtigen Seite liegen.
  test "app_dirs loest einen Programm-Symlink auf" do
    dir = area!("symlink")
    real = Path.join([dir, "checkout", "komki"])
    File.mkdir_p!(Path.dirname(real))
    File.write!(real, "")
    link = Path.join([dir, "bin", "komki"])
    File.mkdir_p!(Path.dirname(link))
    File.ln_s!(real, link)

    assert Nif.app_dirs(link, :ex_pdfium) == [
             Path.join([dir, "checkout", "lib", "ex_pdfium"]),
             Path.join([dir, "checkout", "_build/dev/lib/ex_pdfium"]),
             Path.join([dir, "_build/dev/lib/ex_pdfium"])
           ]
  end

  test "bootstrap: physisches ebin landet auf dem Code-Pfad" do
    dir = area!("bootstrap")
    place!(Path.join([dir, "lib", "ex_pdfium", "ebin"]))
    program = Path.join(dir, "komki")
    File.write!(program, "")

    assert Nif.bootstrap(program, :ex_pdfium) == :ok

    ebin = Path.join([dir, "lib", "ex_pdfium", "ebin"])
    assert ebin in Enum.map(:code.get_path(), &to_string/1)
    :code.del_path(to_charlist(ebin))
  end

  test "bootstrap: ohne Fundstelle bleibt der Code-Pfad unveraendert" do
    before = :code.get_path()
    assert Nif.bootstrap("/opt/komki-golden/bin/komki", :ex_pdfium) == :ok
    assert :code.get_path() == before
  end

  test "bootstrap: ohne Programm (Mix, Release, Burrito) No-Op" do
    before = :code.get_path()
    assert Nif.bootstrap(nil, :ex_pdfium) == :ok
    assert :code.get_path() == before
  end
end
