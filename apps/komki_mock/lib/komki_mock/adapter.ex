defmodule KomkiMock.Adapter do
  @moduledoc """
  What a mock of one external system provides: named seeds and a pure
  request handler. Everything else — the HTTP listeners, the state file,
  reset, scenarios and the request log — is the runtime's job.

  The data an adapter works on must be a JSON value with string keys: the
  runtime writes it to disk after every change and hands the adapter the
  decoded form, so a restart cannot change behaviour.
  """

  @type data :: term()

  @type request :: %{
          method: String.t(),
          path: String.t(),
          query: String.t(),
          headers: [{String.t(), String.t()}],
          body: binary()
        }

  @type response :: {status :: 100..599, headers :: [{String.t(), String.t()}], body :: iodata()}

  @doc "The data a named seed starts from; `:error` for an unknown name."
  @callback seed(name :: String.t()) :: {:ok, data()} | :error

  @doc "Answer one request; return the (possibly changed) data."
  @callback handle(request(), data()) :: {response(), data()}
end
