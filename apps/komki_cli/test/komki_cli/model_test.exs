defmodule KomkiCli.ModelTest do
  @moduledoc """
  Modell-Beschaffung (Ticket #178) mit Fake-curl: kein Test laedt etwas
  aus dem Netz. Dazu der APFS-Klon in `init`.
  """

  use ExUnit.Case, async: true

  alias KomkiCli.{Model, Steps, TestSupport}

  @inhalt "kleines Testmodell"
  @sha Base.encode16(:crypto.hash(:sha256, @inhalt), case: :lower)

  # Fake-curl: Kopfzeilen fuer -sI, sonst schreibt es den Inhalt an den
  # Pfad hinter -o (angehaengt, wie ein fortgesetzter Download) und haelt
  # argv fest.
  defp fake_curl!(dir, opts \\ []) do
    headers = Keyword.get(opts, :headers, "")
    exit_code = Keyword.get(opts, :exit, 0)
    path = Path.join(dir, "curl")

    File.write!(path, """
    #!/bin/sh
    printf '%s\\n' "$*" >> "#{dir}/argv"
    if [ "$1" = "-sI" ]; then printf '%s' '#{headers}'; exit #{exit_code}; fi
    while [ $# -gt 0 ]; do
      if [ "$1" = "-o" ]; then out="$2"; fi
      shift
    done
    printf '%s' '#{Keyword.get(opts, :body, @inhalt)}' >> "$out"
    exit #{exit_code}
    """)

    File.chmod!(path, 0o755)
    path
  end

  describe "remote_matches?/1" do
    test "Prüfsumme der Quelle gleich dem Pin: :ok" do
      dir = TestSupport.tmp_area!("komki-model")
      curl = fake_curl!(dir, headers: ~s(HTTP/2 302\nx-linked-etag: "#{@sha}"\n))
      assert :ok = Model.remote_matches?(command: curl, sha256: @sha)
    end

    test "andere Prüfsumme: Fehler vor jedem Download" do
      dir = TestSupport.tmp_area!("komki-model")
      other = String.duplicate("a", 64)
      curl = fake_curl!(dir, headers: ~s(x-linked-etag: "#{other}"\n))
      assert {:error, reason} = Model.remote_matches?(command: curl, sha256: @sha)
      assert reason =~ "andere Prüfsumme"
    end

    test "ohne Angabe der Quelle: :unknown; nicht erreichbar: Fehler" do
      dir = TestSupport.tmp_area!("komki-model")

      assert :unknown =
               Model.remote_matches?(
                 command: fake_curl!(dir, headers: "HTTP/2 200\n"),
                 sha256: @sha
               )

      dir2 = TestSupport.tmp_area!("komki-model")

      assert {:error, reason} =
               Model.remote_matches?(command: fake_curl!(dir2, exit: 6), sha256: @sha)

      assert reason =~ "nicht erreichbar"
    end
  end

  describe "download/1" do
    test "passende Prüfsumme: Datei liegt am Ziel, kein .part bleibt; curl setzt fort (-C -)" do
      dir = TestSupport.tmp_area!("komki-model")
      dest = Path.join(dir, "modell.gguf")

      assert {:ok, ^dest} =
               Model.download(
                 dest: dest,
                 command: fake_curl!(dir),
                 sha256: @sha,
                 size: 10,
                 url: "https://x/m"
               )

      assert File.read!(dest) == @inhalt
      refute File.exists?(dest <> ".part")
      assert File.read!(Path.join(dir, "argv")) =~ "-C - --progress-bar"
    end

    test "falsche Prüfsumme: Datei wird verworfen, nichts liegt am Ziel" do
      dir = TestSupport.tmp_area!("komki-model")
      dest = Path.join(dir, "modell.gguf")
      curl = fake_curl!(dir, body: "manipuliert")

      assert {:error, reason} =
               Model.download(
                 dest: dest,
                 command: curl,
                 sha256: @sha,
                 size: 10,
                 url: "https://x/m"
               )

      assert reason =~ "Prüfsumme passt nicht"
      refute File.exists?(dest)
      refute File.exists?(dest <> ".part")
    end

    test "Abbruch: Teil-Download bleibt für den naechsten Versuch liegen" do
      dir = TestSupport.tmp_area!("komki-model")
      dest = Path.join(dir, "modell.gguf")
      curl = fake_curl!(dir, exit: 56)

      assert {:error, reason} =
               Model.download(
                 dest: dest,
                 command: curl,
                 sha256: @sha,
                 size: 10,
                 url: "https://x/m"
               )

      assert reason =~ "setzt fort"
      assert File.exists?(dest <> ".part")
      refute File.exists?(dest)
    end

    test "zu wenig Platz: Abbruch vor dem Download" do
      dir = TestSupport.tmp_area!("komki-model")
      dest = Path.join(dir, "modell.gguf")

      assert {:error, reason} =
               Model.download(
                 dest: dest,
                 command: fake_curl!(dir),
                 sha256: @sha,
                 size: 10_000_000_000_000_000,
                 url: "https://x/m"
               )

      assert reason =~ "zu wenig Platz"
      refute File.exists?(Path.join(dir, "argv"))
    end
  end

  test "die URL zeigt auf eine feste Revision, nicht auf main" do
    assert Model.url() =~ ~r"/resolve/[0-9a-f]{40}/"
    refute Model.url() =~ "/resolve/main/"
  end

  describe "MTP-Drafter (Ticket #318): wie das Modell gepinnt" do
    test "die Drafter-URL zeigt auf dieselbe feste Revision, im MTP-Unterordner" do
      assert Model.drafter_url() =~
               ~r"/resolve/[0-9a-f]{40}/MTP/mtp-gemma-4-26B-A4B-it-Q8_0\.gguf$"

      refute Model.drafter_url() =~ "/resolve/main/"
    end

    test "drafter_remote_matches?/1: Pin-Abgleich gegen die Quelle, vor dem Download" do
      dir = TestSupport.tmp_area!("komki-model-dr")
      curl = fake_curl!(dir, headers: ~s(HTTP/2 302\nx-linked-etag: "#{@sha}"\n))
      assert :ok = Model.drafter_remote_matches?(command: curl, sha256: @sha)

      other = String.duplicate("b", 64)

      curl2 =
        fake_curl!(TestSupport.tmp_area!("komki-model-dr"),
          headers: ~s(x-linked-etag: "#{other}"\n)
        )

      assert {:error, reason} = Model.drafter_remote_matches?(command: curl2, sha256: @sha)
      assert reason =~ "andere Prüfsumme"
    end

    test "drafter_download/1: Staging-Ziel, SHA-Gate und Fortsetzen wie beim Modell" do
      dir = TestSupport.tmp_area!("komki-model-dr-dl")
      dest = Path.join(dir, "drafter.gguf")

      assert {:ok, ^dest} =
               Model.drafter_download(
                 dest: dest,
                 command: fake_curl!(dir),
                 sha256: @sha,
                 size: 10
               )

      assert File.read!(dest) == @inhalt
      refute File.exists?(dest <> ".part")

      # Falsche Prüfsumme: eigener Bereich (wie beim gguf-Test), damit am
      # Ziel wirklich nichts liegt.
      dir2 = TestSupport.tmp_area!("komki-model-dr-dl-falsch")
      dest2 = Path.join(dir2, "drafter.gguf")
      curl = fake_curl!(dir2, body: "manipuliert")

      assert {:error, reason} =
               Model.drafter_download(dest: dest2, command: curl, sha256: @sha, size: 10)

      assert reason =~ "Prüfsumme passt nicht"
      refute File.exists?(dest2)
    end

    test "drafter_summary/0 nennt Datei, Quelle und Lizenz" do
      [file, quelle, lizenz] = Model.drafter_summary()

      assert file =~ "Drafter     " <> KomkiCli.Config.drafter_filename()
      assert file =~ " (0,5 GB)"
      assert quelle =~ "huggingface.co/unsloth/gemma-4-26B-A4B-it-GGUF (Revision c099eb48)"
      assert lizenz =~ "Apache-2.0"
    end
  end

  test "clone_or_copy/2 legt eine inhaltsgleiche Datei an (Klon oder Kopie)" do
    dir = TestSupport.tmp_area!("komki-klon")
    source = Path.join(dir, "quelle.gguf")
    dest = Path.join(dir, "ziel.gguf")
    File.write!(source, @inhalt)

    how = Steps.clone_or_copy(source, dest)
    assert how =~ ~r/APFS-Klon|Kopie/
    assert File.read!(dest) == @inhalt
  end
end
