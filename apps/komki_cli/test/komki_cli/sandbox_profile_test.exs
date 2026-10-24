defmodule KomkiCli.SandboxProfileTest do
  @moduledoc """
  Live-Negativproben unter den generierten Profilen (Ticket #146/#137).
  Eine Erlang-Sonde (`test/fixtures/probe.escript`) laeuft als „Binary“
  unter dem jeweiligen Profil — so wie `komki up` startet: `env -i`,
  `sandbox-exec -f <profil> <escript> <datei>`, cwd `/`. Jede Gruppe hat
  eine Positivkontrolle (`nop`), damit ein Nein nicht von einem kaputten
  Profil kommt.

  Nur auf macOS mit sandbox-exec und Erlang-escript (Tag `:sandbox`,
  Ausschluss in test_helper.exs).
  """

  use ExUnit.Case, async: false

  alias KomkiCli.{
    Channel,
    Config,
    ConnectorProfile,
    Connectors,
    Mediator,
    MediatorProfile,
    TestSupport
  }

  alias KomkiConnector.Manifest

  @moduletag :sandbox
  @probe Path.expand("../fixtures/probe.escript", __DIR__)

  setup_all do
    base = Config.canonical(TestSupport.tmp_area!("kst"))
    probe = Config.canonical(@probe)
    File.mkdir_p!(Path.join([base, "vault", "komki-test"]))
    File.write!(Path.join([base, "vault", "notiz.md"]), "# Notiz\n")

    cfg = %{
      Config.defaults(base)
      | escript_bin: Config.resolve_escript_bin(),
        egress_bin: probe,
        mediator_bin: probe,
        connector_bins: Map.new(Manifest.ids(), &{&1, probe})
    }

    Connectors.ensure_run_dirs!(cfg)

    connectors =
      Map.new(Manifest.all(), fn m ->
        {m.id, write(cfg, "connector-" <> m.id, ConnectorProfile.connector(cfg, m))}
      end)

    profiles =
      Map.merge(connectors, %{
        "egress" => write(cfg, "egress", ConnectorProfile.egress(cfg)),
        "mediator" => write(cfg, "mediator", MediatorProfile.generate(cfg, Mediator.listen(cfg)))
      })

    canary = Path.join(System.user_home!(), ".komki-canary-" <> TestSupport.unique_suffix())
    File.write!(canary, "canary\n")
    on_exit(fn -> File.rm(canary) end)

    {:ok, cfg: cfg, profiles: profiles, canary: canary, probe: probe}
  end

  defp write(cfg, name, text) do
    path = Path.join([cfg.base_dir, "profile", name <> ".sb"])
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, text)
    path
  end

  defp probe(ctx, profile, args) do
    {out, rc} =
      System.cmd(
        "/usr/bin/env",
        [
          "-i",
          "HOME=" <> Path.join(ctx.cfg.base_dir, "run"),
          "PATH=/usr/bin:/bin",
          "LANG=C",
          ctx.cfg.sandbox_exec,
          "-f",
          Map.fetch!(ctx.profiles, profile),
          ctx.cfg.escript_bin,
          ctx.probe | args
        ],
        cd: "/",
        stderr_to_stdout: true
      )

    {rc, out}
  end

  defp allowed(ctx, profile, args) do
    {rc, out} = probe(ctx, profile, args)
    assert rc == 0, profile <> " " <> Enum.join(args, " ") <> " sollte gehen: " <> out
  end

  defp denied(ctx, profile, args) do
    {rc, out} = probe(ctx, profile, args)

    assert rc != 0,
           profile <> " " <> Enum.join(args, " ") <> " haette verweigert werden muessen: " <> out
  end

  @all ["ris", "web", "vault", "egress", "mediator"]

  test "Positivkontrolle: jedes Profil bootet die Erlang-Runtime", ctx do
    for p <- @all, do: allowed(ctx, p, ["nop"])
  end

  test "kein Lesen im Home: Canary-Datei und ~/.ssh", ctx do
    ssh = Path.join(System.user_home!(), ".ssh")

    for p <- @all do
      denied(ctx, p, ["read", ctx.canary])
      denied(ctx, p, ["list", ssh])
    end
  end

  test "kein connect zu example.com:443 aus Connector- und Vermittler-Profilen", ctx do
    for p <- ["ris", "web", "vault", "mediator"] do
      denied(ctx, p, ["connect", "example.com", "443"])
      # IP-Literal: verweigert ohne DNS (remote:*:443 im Denial-Log)
      denied(ctx, p, ["connect", "93.184.215.14", "443"])
    end
  end

  test "Vermittler: kein Outbound, auch nicht zu Loopback-Ports der Connectoren", ctx do
    denied(ctx, "mediator", ["connect", "127.0.0.1", "49531"])
    denied(ctx, "mediator", ["connect", "127.0.0.1", "49532"])
  end

  test "Vermittler: eigenen Socket binden, Token lesen, nur Connector-Sockets verbinden", ctx do
    base = ctx.cfg.base_dir
    Channel.write_token!(ctx.cfg)
    allowed(ctx, "mediator", ["bind-unix", Channel.socket_path(ctx.cfg)])
    allowed(ctx, "mediator", ["read", Channel.token_path(ctx.cfg)])
    denied(ctx, "web", ["read", Channel.token_path(ctx.cfg)])

    vault_sock = Manifest.socket_path(base, "vault")
    other_sock = Path.join([base, "run", "other.sock"])

    listeners =
      for path <- [vault_sock, other_sock] do
        File.rm(path)
        {:ok, l} = :gen_tcp.listen(0, ifaddr: {:local, path})
        l
      end

    on_exit(fn -> Enum.each(listeners, &:gen_tcp.close/1) end)

    allowed(ctx, "mediator", ["connect-unix", vault_sock])
    denied(ctx, "mediator", ["connect-unix", other_sock])
    denied(ctx, "web", ["connect-unix", vault_sock])
  end

  test "Proxy-Connector: nur der eigene Egress-Port, nicht der fremde", ctx do
    {:ok, listener} = :gen_tcp.listen(49_532, ip: {127, 0, 0, 1}, reuseaddr: true)
    on_exit(fn -> :gen_tcp.close(listener) end)

    allowed(ctx, "web", ["connect", "127.0.0.1", "49532"])
    denied(ctx, "ris", ["connect", "127.0.0.1", "49532"])
  end

  test "Connector bindet nur den eigenen Socket", ctx do
    allowed(ctx, "vault", ["bind-unix", Manifest.socket_path(ctx.cfg.base_dir, "vault")])
    denied(ctx, "vault", ["bind-unix", Manifest.socket_path(ctx.cfg.base_dir, "web")])
    denied(ctx, "vault", ["bind-unix", Path.join([ctx.cfg.base_dir, "run", "mediator.sock"])])
  end

  test "Vault: lesen im Vault, schreiben nur in komki-test", ctx do
    vault = ctx.cfg.vault_dir
    allowed(ctx, "vault", ["read", Path.join(vault, "notiz.md")])
    allowed(ctx, "vault", ["write", Path.join([vault, "komki-test", "neu.md"])])
    denied(ctx, "vault", ["write", Path.join(vault, "ausserhalb.md")])
    denied(ctx, "vault", ["write", Path.join([ctx.cfg.base_dir, "tmp", "x.log"])])
    # andere Connectoren sehen den Vault nicht
    denied(ctx, "web", ["read", Path.join(vault, "notiz.md")])
  end
end
