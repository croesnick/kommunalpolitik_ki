# sidecar

A framed, capability-token protocol for sandboxed sidecar processes over
Unix domain sockets — in Elixir, with zero runtime dependencies (JSON comes
from OTP's `:json`, so OTP 27+).

This is the protocol komki uses between its broker and its sandboxed
connectors. It was extracted from `komki_connector`
([issue #225](https://github.com/croesnick/kommunalpolitik_ki/issues/225))
as a candidate for a standalone Hex package, which is why code and docs are
deliberately English.

## The protocol, in short

- **One connection per call.** Connect, one request, one response, close.
  The caller never shares a connection, the sidecar never keeps one open.
- **Framed JSON.** 4 bytes of big-endian length, then UTF-8 JSON, at most
  1 MiB per frame. A larger frame is a protocol error and closes the
  connection.
- **Capability token before anything else.** `komki up` — or whatever starts
  the sidecar — generates a 32-byte random token per start, hands it to the
  sidecar over stdin and keeps it in a `0600` file beside the socket. Every
  request must carry it; the comparison runs in constant time and happens
  before `ping`, before schema validation, before any operation. An
  unauthorized caller does not even learn the `call_id` it sent.
- **Semantic operations, not a generic surface.** A sidecar declares a
  manifest of operations with closed parameter schemas (`Sidecar.Params`):
  unknown fields are rejected, defaults are filled, strings are bounded by
  length and pattern. `handle_op/4` never sees an unchecked argument.
- **Errors are a closed set.** `bad-request`, `unknown-op`, `not-found`,
  `upstream-error`, `upstream-timeout`, `credential-missing`,
  `forbidden-path`, `too-large`, `unauthorized`, `internal`. Whatever detail
  a sidecar writes into an error reply stays in its log — the client
  replaces it with the fixed text of the code, so no sidecar free text ever
  crosses the socket boundary into the caller's context.
- **Optional peer-credential check.** Where the platform allows it
  (`SO_PEERCRED` on Linux, `LOCAL_PEERCRED` on macOS) the server can
  additionally require that a caller's peer uid matches the sidecar's own —
  defense in depth against other processes of a loosened socket directory.

## Quick start

A sidecar implements `Sidecar.Server` and runs it from its entry point:

```elixir
defmodule MySidecar do
  @behaviour Sidecar.Server

  @impl true
  def manifest do
    %{
      fassung: "my-sidecar/1",
      ops: %{
        "search" => %{
          params: %{"text" => %{type: :string, max: 200, required: true}},
          kind: :read
        }
      }
    }
  end

  @impl true
  def init(_args), do: {:ok, %{}}

  @impl true
  def handle_op("search", %{"text" => text}, _context, state) do
    {:ok, %{"hits" => search(text)}}
  end
end

# In the sidecar's main: read credentials (the token) from stdin, then serve.
{:ok, creds} = Sidecar.Server.read_credentials()
Sidecar.Server.run(MySidecar, socket_path, nil, creds,
  credential_key: "MY_SIDECAR_TOKEN",
  peer_credentials: true
)
```

The caller side — one call, one connection:

```elixir
Sidecar.Client.call(socket_path, call_id, "search", %{"text" => "hello"})
#=> {:ok, %{"hits" => [...]}} | {:error, %{"code" => "not-found", "detail" => "not found"}}
```

The reserved operation `ping` is answered by the server itself, from the
manifest: it reports the manifest's `fassung` and its operation names.

## Texts

Every string that a caller may surface to its own users — the fixed text per
error code, transport failure details, parameter-validation details — comes
from a `Sidecar.Texts` module. The library ships English defaults; pass your
own implementation to `Sidecar.Client.call/6` (`texts:` option) and
`Sidecar.Params.check/3` to control the language of those texts. The wire
`"fassung"` key of `ping` is historical protocol vocabulary and stays as-is
for compatibility.

## Options

- `Sidecar.Server.run/5` — `credential_key:` (the stdin-credentials key that
  holds the token, default `"SIDECAR_TOKEN"`), `peer_credentials:` (`false`
  (default) | `true` | an expected uid integer).
- `Sidecar.Client.call/6` — `timeout:` (default 15 s), `texts:` (default
  `Sidecar.Texts`).
- `Sidecar.Params.check/3` — `texts:` (default `Sidecar.Texts`).

## Layout

| Module             | Role                                                        |
| ------------------ | ----------------------------------------------------------- |
| `Sidecar.Frame`    | Wire codec: framing constants, request/reply shapes, codes  |
| `Sidecar.Token`    | Capability tokens: generate, provision beside the socket, verify |
| `Sidecar.Params`   | Closed parameter schemas: check and normalize               |
| `Sidecar.Texts`    | Caller-visible texts: defaults in English, injectable       |
| `Sidecar.Client`   | Caller side: one connection per call, detail suppression    |
| `Sidecar.Server`   | Sidecar side: behaviour, accept loop, token-first auth, optional peer-uid check |
