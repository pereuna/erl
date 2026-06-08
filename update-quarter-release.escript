#!/usr/bin/env escript
%% -*- erlang -*-
%%! -noshell

-include_lib("kernel/include/file.hrl").

-define(SRC, "_build/default/rel/quarter").
-define(DEST, "/usr/local/quarter").
-define(OWNER, "_quarter:_quarter").

main([]) ->
    Src = ?SRC,
    Dest = ?DEST,
    Owner = ?OWNER,
    Tmp = Dest ++ ".new." ++ os:getpid(),
    Old = Dest ++ ".old." ++ os:getpid(),

    ensure_release(Src),
    ok = remove_path(Tmp),
    ok = remove_path(Old),
    ok = make_dir(Tmp),
    ok = copy_tree(Src, Tmp),
    ok = run("chown", ["-R", Owner, Tmp]),
    ok = replace_release(Dest, Tmp, Old),
    ok = remove_path(Old),
    io:format("Päivitetty: ~s~n", [Dest]);
main(_) ->
    fail("Käyttö: ./update-quarter-release.escript").

ensure_release(Src) ->
    StartScript = filename:join([Src, "bin", "quarter"]),
    case file:read_file_info(StartScript) of
        {ok, #file_info{type = regular, mode = Mode}} when Mode band 8#111 =/= 0 ->
            ok;
        {ok, _} ->
            fail("Release-skripti ei ole ajettava tiedosto: ~s", [StartScript]);
        {error, _} ->
            fail("Releaseä ei löydy: ~s~nAja ensin: rebar3 release", [StartScript])
    end.

replace_release(Dest, Tmp, Old) ->
    case path_exists(Dest) of
        true -> ok = rename(Dest, Old);
        false -> ok
    end,
    case file:rename(Tmp, Dest) of
        ok ->
            ok;
        {error, Reason} ->
            _ = case path_exists(Old) of
                    true -> file:rename(Old, Dest);
                    false -> ok
                end,
            fail("Hakemiston ~s käyttöönotto epäonnistui: ~p", [Dest, Reason])
    end.

copy_tree(Src, Dst) ->
    case file:read_link_info(Src) of
        {ok, #file_info{type = directory, mode = Mode}} ->
            ok = make_dir(Dst),
            ok = change_mode(Dst, Mode band 8#7777),
            {ok, Names} = file:list_dir(Src),
            lists:foreach(
              fun(Name) ->
                  ok = copy_tree(filename:join(Src, Name), filename:join(Dst, Name))
              end,
              Names),
            ok;
        {ok, #file_info{type = symlink}} ->
            {ok, LinkTarget} = file:read_link(Src),
            ok = file:make_symlink(LinkTarget, Dst);
        {ok, #file_info{type = regular, mode = Mode}} ->
            {ok, _BytesCopied} = file:copy(Src, Dst),
            ok = change_mode(Dst, Mode band 8#7777);
        {ok, #file_info{type = Type}} ->
            fail("Tiedostotyyppiä ei tueta (~p): ~s", [Type, Src]);
        {error, Reason} ->
            fail("Tiedoston lukeminen epäonnistui (~p): ~s", [Reason, Src])
    end.

remove_path(Path) ->
    case file:read_link_info(Path) of
        {ok, #file_info{type = directory}} ->
            {ok, Names} = file:list_dir(Path),
            lists:foreach(fun(Name) -> ok = remove_path(filename:join(Path, Name)) end, Names),
            file:del_dir(Path);
        {ok, _} ->
            file:delete(Path);
        {error, enoent} ->
            ok;
        {error, Reason} ->
            fail("Polun poistaminen epäonnistui (~p): ~s", [Reason, Path])
    end.

path_exists(Path) ->
    case file:read_link_info(Path) of
        {ok, _} -> true;
        {error, enoent} -> false;
        {error, Reason} -> fail("Polun tarkistus epäonnistui (~p): ~s", [Reason, Path])
    end.

make_dir(Path) ->
    case file:make_dir(Path) of
        ok -> ok;
        {error, eexist} -> ok;
        {error, eacces} -> fail("Ei oikeuksia luoda hakemistoa: ~s~nAja tarvittaessa: doas ./update-quarter-release.escript", [Path]);
        {error, Reason} -> fail("Hakemiston luonti epäonnistui (~p): ~s", [Reason, Path])
    end.

rename(From, To) ->
    case file:rename(From, To) of
        ok -> ok;
        {error, eacces} -> fail("Ei oikeuksia siirtää hakemistoa: ~s~nAja tarvittaessa: doas ./update-quarter-release.escript", [From]);
        {error, Reason} -> fail("Hakemiston siirto epäonnistui (~p): ~s -> ~s", [Reason, From, To])
    end.

change_mode(Path, Mode) ->
    case file:change_mode(Path, Mode) of
        ok -> ok;
        {error, Reason} -> fail("Tiedoston oikeuksien asetus epäonnistui (~p): ~s", [Reason, Path])
    end.

run(Command, Args) ->
    case os:find_executable(Command) of
        false ->
            fail("Komentoa ei löydy: ~s", [Command]);
        Executable ->
            Port = open_port({spawn_executable, Executable}, [exit_status, {args, Args}, stderr_to_stdout]),
            wait_port(Port, Command, Args, [])
    end.

wait_port(Port, Command, Args, Output) ->
    receive
        {Port, {data, Data}} ->
            wait_port(Port, Command, Args, [Output, Data]);
        {Port, {exit_status, 0}} ->
            ok;
        {Port, {exit_status, Status}} ->
            fail("Komento epäonnistui (~B): ~s ~s~n~s", [Status, Command, string:join(Args, " "), lists:flatten(Output)])
    end.

fail(Format) ->
    fail(Format, []).

fail(Format, Args) ->
    io:format(standard_error, Format ++ "~n", Args),
    halt(1).
