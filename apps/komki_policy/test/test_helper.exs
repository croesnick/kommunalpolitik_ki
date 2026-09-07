# Property-Runs sind reproduziert: die Run-Zahl ist als App-Env fix.
# Der Seed wird pro Property in property_test.exs gesetzt (Option
# :initial_seed der `check all`-Bloecke). StreamData liest :initial_seed
# nicht aus der App-Env; seine Default-Quelle ist ExUnit's Seed, d. h.
# `mix test --seed <N>` reproduziert ebenfalls jeden Lauf.
# Bei einem Fehlschlag denselben Befehl erneut laufen lassen: der
# Pruefling wird vom selben Seed genauso erzeugt.
Application.put_env(:stream_data, :max_runs, 200)

ExUnit.start()
