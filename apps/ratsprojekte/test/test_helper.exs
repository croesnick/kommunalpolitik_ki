# The fixture migrations of the local-operation tests (#440) are loaded again
# for every throwaway home.
Code.put_compiler_option(:ignore_module_conflict, true)

ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Ratsprojekte.Repo, :manual)
