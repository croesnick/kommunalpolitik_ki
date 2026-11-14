# elixir scripts/changesets/test/core_test.exs

ExUnit.start()
Code.require_file("../core.exs", __DIR__)

defmodule Changesets.CoreTest do
  use ExUnit.Case, async: true

  alias Changesets.Core

  @knope_toml """
  [packages.komki]
  versioned_files = [{ path = "apps/komki_cli/mix.exs", regex = 'version: "(?<version>\\d+\\.\\d+\\.\\d+)"' }]
  changelog = "apps/komki_cli/CHANGELOG.md"

  [packages.ratsprojekte]
  versioned_files = [{ path = "apps/ratsprojekte/mix.exs", regex = 'version: "(?<version>\\d+\\.\\d+\\.\\d+)"' }]
  changelog = "apps/ratsprojekte/CHANGELOG.md"

  [packages.sealed_envelope]
  versioned_files = [{ path = "apps/sealed_envelope/mix.exs", regex = 'version: "(?<version>\\d+\\.\\d+\\.\\d+)"' }]
  changelog = "apps/sealed_envelope/CHANGELOG.md"

  [packages.seatbelt]
  versioned_files = [{ path = "apps/seatbelt/mix.exs", regex = 'version: "(?<version>\\d+\\.\\d+\\.\\d+)"' }]
  changelog = "apps/seatbelt/CHANGELOG.md"
  """

  @units %{
    "komki" => "apps/komki_cli",
    "ratsprojekte" => "apps/ratsprojekte",
    "sealed_envelope" => "apps/sealed_envelope",
    "seatbelt" => "apps/seatbelt"
  }

  test "units come from the package sections of knope.toml" do
    assert Core.units(@knope_toml) == @units
  end

  test "the knope.toml of the repo names the five units" do
    toml = File.read!(Path.expand("../../../knope.toml", __DIR__))

    assert Core.units(toml) == %{
             "komki" => "apps/komki_cli",
             "ratsprojekte" => "apps/ratsprojekte",
             "sidecar" => "apps/sidecar",
             "seatbelt" => "apps/seatbelt",
             "sealed_envelope" => "apps/sealed_envelope"
           }
  end

  describe "parse_changeset/1" do
    test "reads one or more units with their level" do
      text = "---\nkomki: minor\n\"sidecar\": patch\n---\n\n# Neue Option\n"
      assert Core.parse_changeset(text) == {:ok, %{"komki" => "minor", "sidecar" => "patch"}}
    end

    test "rejects an unknown level and a missing frontmatter" do
      assert {:error, _} = Core.parse_changeset("---\nkomki: feature\n---\n# x\n")
      assert {:error, _} = Core.parse_changeset("# nur Text\n")
    end

    test "unknown/2 names units knope.toml does not list" do
      assert Core.unknown(@units, %{"komki" => "patch", "komk" => "patch"}) == ["komk"]
    end
  end

  # komki ships the mediator, which brings the policy engine and seatbelt.
  @deps %{
    "apps/komki_cli" => ["apps/komki_mediator", "apps/sealed_envelope"],
    "apps/komki_mediator" => ["apps/komki_policy", "apps/seatbelt"],
    "apps/ratsprojekte" => ["apps/sealed_envelope"],
    "apps/ratsinfo" => ["apps/shared"]
  }

  describe "path_deps/1 and bundles/2" do
    test "runtime path dependencies; only: deps are tooling and do not ship" do
      source =
        ~s|{:sidecar, path: "../sidecar"}, {:komki_mock, path: "../komki_mock", only: :test}, {:jason, "~> 1.4"}|

      assert Core.path_deps(source) == ["apps/sidecar"]
    end

    test "a unit's bundle reaches through other apps and stops at units" do
      assert Core.bundles(@units, @deps) == %{
               "komki" => ["apps/komki_cli", "apps/komki_mediator", "apps/komki_policy"],
               "ratsprojekte" => ["apps/ratsprojekte"],
               "sealed_envelope" => ["apps/sealed_envelope"],
               "seatbelt" => ["apps/seatbelt"]
             }
    end

    test "komki's bundle in the repo holds mediator, policy, egress and connectors, no mocks" do
      root = Path.expand("../../..", __DIR__)
      units = Core.units(File.read!(Path.join(root, "knope.toml")))

      deps =
        for file <- Path.wildcard(Path.join(root, "apps/*/mix.exs")),
            into: %{},
            do: {"apps/" <> Path.basename(Path.dirname(file)), Core.path_deps(File.read!(file))}

      komki = Core.bundles(units, deps)["komki"]

      for app <-
            ~w(komki_cli komki_mediator komki_policy komki_egress komki_connector komki_connector_ris),
          do: assert("apps/#{app}" in komki)

      for app <- ~w(komki_mock wegwerf_hub sidecar seatbelt sealed_envelope ratsprojekte),
          do: refute("apps/#{app}" in komki)

      assert Core.bundles(units, deps)["ratsprojekte"] == ["apps/ratsprojekte"]
    end
  end

  describe "missing/3" do
    setup do: %{bundles: Core.bundles(@units, @deps)}

    test "a change to lib/ or priv/ needs a changeset naming the unit", %{bundles: b} do
      changed = ["apps/komki_cli/lib/komki_cli/cli.ex", "apps/seatbelt/priv/base.sb"]
      assert Core.missing(b, changed, []) == ["komki", "seatbelt"]
      assert Core.missing(b, changed, [%{"komki" => "minor"}]) == ["seatbelt"]
      assert Core.missing(b, changed, [%{"komki" => "minor", "seatbelt" => "patch"}]) == []
    end

    test "a change in an app of the bundle counts for the unit", %{bundles: b} do
      assert Core.missing(b, ["apps/komki_mediator/lib/komki_mediator/gate.ex"], []) == ["komki"]
      assert Core.missing(b, ["apps/komki_policy/priv/x.json"], [%{"komki" => "patch"}]) == []
    end

    test "tests, mix.exs, docs and apps outside every bundle need none", %{bundles: b} do
      changed = [
        "apps/komki_cli/test/cli_test.exs",
        "apps/komki_cli/mix.exs",
        "apps/komki_mediator/test/gate_test.exs",
        "apps/komki_cli/README.md",
        "apps/ratsinfo/lib/ratsinfo.ex",
        "docs/release.md"
      ]

      assert Core.missing(b, changed, []) == []
    end

    test "a directory sharing a prefix is not the unit", %{bundles: b} do
      assert Core.missing(b, ["apps/komki_cli_extra/lib/x.ex"], []) == []
    end
  end

  test "version/1 reads the project version" do
    assert Core.version(~s|def project, do: [app: :x, version: "0.2.1", elixir: "~> 1.19"]|) ==
             "0.2.1"
  end

  describe "dependents/3 and cascade/2" do
    test "units included anywhere in a bundle, transitively" do
      dependents = Core.dependents(@units, Core.bundles(@units, @deps), @deps)
      sorted = Map.new(dependents, fn {lib, units} -> {lib, Enum.sort(units)} end)
      assert sorted == %{"seatbelt" => ["komki"], "sealed_envelope" => ["komki", "ratsprojekte"]}
    end

    test "a bumped library gives each dependent that was not bumped a patch" do
      deps = %{"seatbelt" => ["komki"], "sealed_envelope" => ["komki", "ratsprojekte"]}

      assert Core.cascade(deps, %{"seatbelt" => "0.1.1", "sealed_envelope" => "0.2.0"}) == [
               {"komki", [{"sealed_envelope", "0.2.0"}, {"seatbelt", "0.1.1"}]},
               {"ratsprojekte", [{"sealed_envelope", "0.2.0"}]}
             ]
    end

    test "a dependent with its own bump gets no cascade" do
      deps = %{"seatbelt" => ["komki"]}
      assert Core.cascade(deps, %{"seatbelt" => "0.1.1", "komki" => "0.2.0"}) == []
      assert Core.cascade(deps, %{}) == []
    end

    test "the cascade changeset is a patch that parses back" do
      text = Core.cascade_changeset("komki", [{"seatbelt", "0.1.1"}])
      assert Core.parse_changeset(text) == {:ok, %{"komki" => "patch"}}
      assert text =~ "\n# Enthält seatbelt 0.1.1\n"

      text =
        Core.cascade_changeset("komki", [
          {"sealed_envelope", "0.2.0"},
          {"seatbelt", "0.1.1"},
          {"sidecar", "0.1.1"}
        ])

      assert text =~ "# Enthält sealed_envelope 0.2.0, seatbelt 0.1.1 und sidecar 0.1.1\n"
    end
  end
end
