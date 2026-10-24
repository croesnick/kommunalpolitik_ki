# Tests mit dem macOS-Dateiflag uappnd (Ticket #139) brauchen /usr/bin/chflags;
# auf der Linux-CI gibt es das nicht.
exclude = if File.exists?("/usr/bin/chflags"), do: [], else: [:chflags]

# Live-Negativproben unter den generierten Profilen (Ticket #146): nur mit
# sandbox-exec (macOS) und einer aufloesbaren Erlang-escript-Laufzeit.
sandbox? =
  File.exists?("/usr/bin/sandbox-exec") and is_binary(KomkiCli.Config.resolve_escript_bin())

exclude = if sandbox?, do: exclude, else: [:sandbox | exclude]
ExUnit.start(exclude: exclude)

# Ticket #146: kein Test fragt den echten Schluesselbund ab (auch nicht der
# volle Doctor im DoctorBootTest). /usr/bin/false: "Abfrage fehlgeschlagen".
Application.put_env(:komki_cli, :security, "/usr/bin/false")
