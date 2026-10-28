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

# Kein Test fragt die echte Secure Enclave: Der Fake-Tresor "versiegelt"
# per Base64 hinter dem echten Praefix und oeffnet ohne Rueckfrage.
fake_tresor =
  Path.join(System.tmp_dir!(), "komki-fake-tresor-#{System.unique_integer([:positive])}")

File.write!(fake_tresor, """
#!/bin/sh
case "$1" in
  check) exit 0 ;;
  seal) read -r v; printf 'ktv1.%s\n' "$(printf '%s' "$v" | base64 | tr -d '\\n')" ;;
  open) read -r v; printf '%s' "${v#ktv1.}" | base64 -d; echo ;;
  *) exit 2 ;;
esac
""")

File.chmod!(fake_tresor, 0o755)
Application.put_env(:komki_cli, :tresor, fake_tresor)
