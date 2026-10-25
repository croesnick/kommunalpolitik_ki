defmodule KomkiCli.PnpmDiscoveryTest do
  # async: false, weil der Test PNPM_HOME setzt.
  use ExUnit.Case, async: false

  alias KomkiCli.{Config, TestSupport}

  @bundle "node_modules/@earendil-works/pi-coding-agent/dist/bundle/cli.js"

  setup do
    previous = System.get_env("PNPM_HOME")
    home = TestSupport.tmp_area!("komki-pnpm")
    System.put_env("PNPM_HOME", home)

    on_exit(fn ->
      if previous, do: System.put_env("PNPM_HOME", previous), else: System.delete_env("PNPM_HOME")
    end)

    %{home: home}
  end

  defp place!(path) do
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, "")
    Config.canonical(path)
  end

  test "pnpm ab 11: global/v<n>/<id>/node_modules", %{home: home} do
    cli = place!(Path.join([home, "global", "v11", "3391-abc-0", @bundle]))
    assert Config.resolve_cli_js(nil) == cli
  end

  test "pnpm bis 10: global/<n>/node_modules", %{home: home} do
    cli = place!(Path.join([home, "global", "5", @bundle]))
    assert Config.resolve_cli_js(nil) == cli
  end

  test "pnpm vor dem npm-Baum des entdeckten node", %{home: home} do
    cli = place!(Path.join([home, "global", "v11", "x", @bundle]))
    node_install = TestSupport.tmp_area!("komki-node")
    place!(Path.join([node_install, "lib", @bundle]))

    assert Config.resolve_cli_js(Path.join([node_install, "bin", "node"])) == cli
  end
end
