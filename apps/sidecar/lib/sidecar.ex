defmodule Sidecar do
  @moduledoc """
  A framed, capability-token protocol for sandboxed sidecar processes over
  Unix domain sockets.

  A sidecar implements the `Sidecar.Server` behaviour (its manifest of
  operations plus `handle_op/4`) and runs `Sidecar.Server.run/5`; callers —
  typically a broker process — use `Sidecar.Client.call/6`:

      {:ok, creds} = Sidecar.Server.read_credentials()
      Sidecar.Server.run(MySidecar, socket_path, init_arg, creds)

      Sidecar.Client.call(socket_path, call_id, "search", %{"text" => "..."})

  Protocol v1, in one sentence per rule:

  - One connection per call: connect, one request, one response, close.
  - Frames are 4 bytes of big-endian length followed by UTF-8 JSON,
    at most 1 MiB per frame (`Sidecar.Frame`).
  - Every request carries a capability token, generated per sidecar start
    and compared in constant time — checked before anything else, so an
    unauthorized caller learns nothing (`Sidecar.Token`).
  - Operation parameters are validated against the manifest's closed
    schema before `handle_op/4` runs (`Sidecar.Params`).
  - Error replies carry a code from a closed set; the detail written by
    a sidecar never reaches the caller — the client replaces it with the
    fixed text of the code (`Sidecar.Texts`).

  Extracted from komki's `komki_connector` (issue #225); deliberately
  English in code and docs because it is a candidate for a standalone
  Hex package. The sidecar's own logs and stderr are in English; texts
  that a caller surfaces to its users are injectable via `Sidecar.Texts`.
  """
end
