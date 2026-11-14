defmodule Seatbelt.TestSupport do
  @moduledoc false

  import ExUnit.Callbacks, only: [on_exit: 1]

  # Unique scratch directory per test, removed on exit.
  @spec tmp_area!(String.t()) :: String.t()
  def tmp_area!(prefix) do
    dir = Path.join(tmp_root(), prefix <> "-" <> unique_suffix())

    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)

    dir
  end

  # Short root: keep generated paths well under the 103-byte socket path
  # limit; /tmp where it exists (the macOS TMPDIR under /var/folders/...
  # is too long), otherwise System.tmp_dir!/0.
  defp tmp_root, do: if(File.dir?("/tmp"), do: "/tmp", else: System.tmp_dir!())

  defp unique_suffix, do: Integer.to_string(:erlang.unique_integer([:positive]), 36)
end
