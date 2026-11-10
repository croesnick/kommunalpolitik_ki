# Tests mit dem macOS-Dateiflag uappnd (Ticket #139) brauchen /usr/bin/chflags;
# auf der Linux-CI gibt es das nicht.
exclude = if File.exists?("/usr/bin/chflags"), do: [], else: [:chflags]

# Live-Negativproben unter den generierten Profilen (Ticket #146): nur mit
# sandbox-exec (macOS) und einer aufloesbaren Erlang-escript-Laufzeit.
sandbox? =
  File.exists?("/usr/bin/sandbox-exec") and is_binary(KomkiCli.Config.resolve_escript_bin())

exclude = if sandbox?, do: exclude, else: [:sandbox | exclude]

# Echter llama-server-Boot (DoctorBootTest, Ticket #392): nur mit
# `mix test --include llama_boot`, nie im Standardlauf.
exclude = [:llama_boot | exclude]

# Real Secure Enclave with a Touch ID prompt (TresorLiveTest, ticket #337):
# only with `mix test --include touch_id`, never in a standard run or on CI.
exclude = [:touch_id | exclude]
ExUnit.start(exclude: exclude)

# Ticket #146: kein Test fragt den echten Schluesselbund ab (auch nicht der
# volle Doctor im DoctorBootTest). /usr/bin/false: "Abfrage fehlgeschlagen".
Application.put_env(:komki_cli, :security, "/usr/bin/false")

# Kein Test fragt die echte Secure Enclave: Der Fake-Tresor spricht das
# Protokoll des echten Programms mit echtem ECDH, ohne Rueckfrage. PATH steht
# fest im Wrapper, weil einzelne Tests PATH leeren.
fake_tresor =
  Path.join(System.tmp_dir!(), "komki-fake-tresor-#{System.unique_integer([:positive])}")

File.write!(fake_tresor, """
#!/bin/sh
[ "$1" = check ] && exit 0
PATH='#{System.get_env("PATH")}' exec elixir #{Path.expand("support/fake_tresor.exs", __DIR__)} "$@"
""")

File.chmod!(fake_tresor, 0o755)
Application.put_env(:komki_cli, :tresor, fake_tresor)
