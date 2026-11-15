defmodule KomkiMock.StateDirTest do
  # Ticket #481: Lage-Prüfung des Zustandsverzeichnisses nach dem Vorbild
  # von ris_recorder.exs check_out — inklusive des Symlink-Falls.
  use ExUnit.Case, async: true

  alias KomkiMock.StateDir

  defp tmp(name) do
    dir = Path.join(System.tmp_dir!(), "state-dir-" <> name <> "-" <> unique())
    on_exit(fn -> File.rm_rf(dir) end)
    dir
  end

  defp unique, do: Integer.to_string(System.unique_integer([:positive]))

  defp fake_repo(name) do
    repo = tmp(name)
    File.mkdir_p!(Path.join(repo, ".git"))
    repo
  end

  test "check/2: außerhalb jedes Repos ist :ok" do
    assert :ok = StateDir.check(KomkiMock.Adapters.Replay, tmp("frei"))
  end

  test "check/2: Zustandsverzeichnis im Git-Repo wird verweigert" do
    repo = fake_repo("repo")
    state = Path.join(repo, "zustand")

    assert {:error, reason} = StateDir.check(KomkiMock.Adapters.Replay, state)
    assert reason =~ "Git-Repo"
    assert reason =~ "zustand"
  end

  test "check/2: Symlink, der in ein Git-Repo führt, wird aufgelöst" do
    repo = fake_repo("repo-symlink")
    link = tmp("link")
    File.ln_s!(repo, link)

    assert {:error, reason} =
             StateDir.check(KomkiMock.Adapters.Replay, Path.join(link, "zustand"))

    assert reason =~ "Git-Repo"
  end

  test "check/2: andere Adapter bleiben unberührt (auch im Repo)" do
    repo = fake_repo("repo-notes")
    assert :ok = StateDir.check(KomkiMock.Adapters.Notes, Path.join(repo, "zustand"))
  end
end
