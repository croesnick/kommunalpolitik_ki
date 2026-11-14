# The fixture migrations of the local-operation tests (#440) are loaded again
# for every throwaway home.
Code.put_compiler_option(:ignore_module_conflict, true)

# macOS-only tests (plutil) are skipped on the Linux CI.
ExUnit.start(exclude: if(match?({:unix, :darwin}, :os.type()), do: [], else: [:macos]))
Ecto.Adapters.SQL.Sandbox.mode(Ratsprojekte.Repo, :manual)
