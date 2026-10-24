#!/usr/bin/env escript
%%! -noinput
%% Sonde fuer die Live-Negativproben (Ticket #146): fuehrt genau eine
%% Operation aus und endet mit 0 (Erfolg) oder 1 (verweigert/Fehler).
main(Args) ->
    R = (catch run(Args)),
    io:format("~p~n", [R]),
    case R of ok -> halt(0); {ok, _} -> halt(0); _ -> halt(1) end.
run(["read", P]) -> file:read_file(P);
run(["write", P]) -> file:write_file(P, <<"x">>);
run(["list", P]) -> file:list_dir(P);
run(["connect", H, Po]) -> gen_tcp:connect(H, list_to_integer(Po), [], 3000);
run(["connect-unix", P]) -> gen_tcp:connect({local, P}, 0, [], 3000);
run(["bind-unix", P]) ->
    file:delete(P),
    {ok, L} = gen_tcp:listen(0, [{ifaddr, {local, P}}]),
    ok = file:change_mode(P, 8#600),
    {ok, L};
run(["stdin"]) -> {ok, io:get_line("")};
run(["nop"]) -> ok.
