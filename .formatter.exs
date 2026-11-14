[
  inputs: [
    "{mix,.formatter,.credo,.workspace}.exs",
    "{config,lib,test}/**/*.{ex,exs}",
    "apps/*/mix.exs",
    "apps/*/{config,lib,test}/**/*.{ex,exs}",
    "scripts/**/*.{ex,exs}",
    ".claude/hooks/**/*.exs"
  ],
  import_deps: []
]
