%% entso_run.erl
%% Laskee vanhan /rc/trilogy.rc + trilogy-awk -ketjun tuottaman run.txt-suunnitelman.
-module(entso_run).

-export([plan_day/1, plan_day/2, plan_day/4]).

-define(DEFAULT_VAR_DIR, "/var/www/htdocs/jedi.ydns.eu/var").
-define(VVARAAJA, 2.0).
-define(U, 1.17).

plan_day(Day) ->
    VarDir = getenv("QUARTER_VAR_DIR", ?DEFAULT_VAR_DIR),
    DayDir = filename:join([VarDir | string:split(Day, "-", all)]),
    plan_day(
        filename:join(DayDir, "prices.txt"),
        filename:join(DayDir, "temps.txt")
    ).

plan_day(PricesFile, TempsFile) ->
    plan_day(PricesFile, TempsFile, entso_tables:p55(), entso_tables:cop55()).

plan_day(PricesFile, TempsFile, P55, COP55) ->
    DayDir = filename:dirname(TempsFile),
    TriFile = filename:join(DayDir, "tri.txt"),
    RunFile = filename:join(DayDir, "run.txt"),
    Prices = prices(PricesFile),
    Temps = temps(TempsFile),
    Rows = rows(Temps, Prices, P55, COP55),
    Run = run_lines(Rows),
    ok = file:write_file(TriFile, tri_txt(Rows)),
    ok = file:write_file(RunFile, Run),
    {ok, #{tri => TriFile, run => RunFile, rows => length(Rows)}}.

rows(Temps, Prices, P55, COP55) ->
    [row(Time, Temp, price_at(Time, Prices), P55, COP55) || {Time, Temp} <- Temps].

row(Time, Temp, Price, P55, COP55) ->
    P55Value = table_value(Temp, P55, "P55"),
    COP55Value = table_value(Temp, COP55, "COP55"),
    Rhinta = ((Price + 63.3) * 1.24) / COP55Value,
    Ptarve = -0.2 * Temp + 6,
    Pvarasto = P55Value - Ptarve,
    Tdiff = 55 - (-0.0067 * Temp - 0.9 * Temp + 42.7),
    Udiff = Tdiff * ?VVARAAJA * ?U,
    #{time => Time, temp => Temp, price => Price, rhinta => Rhinta,
      ptarve => Ptarve, pvarasto => Pvarasto, udiff => Udiff}.

run_lines(Rows) ->
    Cheapest = lists:sort(fun cheaper_first/2, Rows),
    Expensive = lists:sort(fun pricier_first/2, Rows),
    unicode:characters_to_binary(select_lines(Cheapest, pvarasto, "L") ++ select_lines(Expensive, ptarve, "P")).

cheaper_first(A, B) ->
    sort_key(A) < sort_key(B).

pricier_first(A, B) ->
    sort_key(A) > sort_key(B).

sort_key(Row) ->
    {maps:get(rhinta, Row), maps:get(time, Row)}.

select_lines(Rows, SumKey, Label) ->
    select_lines(Rows, SumKey, Label, 0.0, []).

select_lines([], _SumKey, _Label, _Acc, Out) ->
    lists:reverse(Out);
select_lines([Row | Rest], SumKey, Label, Acc0, Out) ->
    Acc = Acc0 + maps:get(SumKey, Row),
    Line = io_lib:format("~s\t~s~n", [maps:get(time, Row), Label]),
    Out1 = [Line | Out],
    case Acc > maps:get(udiff, Row) of
        true -> lists:reverse(Out1);
        false -> select_lines(Rest, SumKey, Label, Acc, Out1)
    end.

tri_txt(Rows) ->
    unicode:characters_to_binary([tri_line(Row) || Row <- Rows]).

tri_line(Row) ->
    io_lib:format("~s\t~.2f\t~.2f\t~.2f\t~.2f\t~.2f~n", [
        maps:get(time, Row),
        maps:get(price, Row),
        maps:get(rhinta, Row),
        maps:get(ptarve, Row),
        maps:get(pvarasto, Row),
        maps:get(udiff, Row)
    ]).

temps(File) ->
    {ok, Bin} = file:read_file(File),
    Lines = string:split(unicode:characters_to_list(Bin), "\n", all),
    [temp_line(Line) || Line0 <- Lines, (Line = string:trim(Line0)) =/= ""].

temp_line(Line) ->
    [Time, TempS | _] = string:lexemes(Line, " \t"),
    {Temp, []} = string:to_integer(TempS),
    {Time, Temp}.

prices(File) ->
    {ok, Bin} = file:read_file(File),
    Lines = string:split(unicode:characters_to_list(Bin), "\n", all),
    maps:from_list([price_line(Line) || Line0 <- Lines, (Line = string:trim(Line0)) =/= ""]).

price_line(Line) ->
    [Time, PriceS | _] = string:lexemes(Line, " \t"),
    {Time, parse_float(PriceS)}.

price_at(Time, Prices) ->
    case maps:get(Time, Prices, undefined) of
        undefined -> error({missing_price, Time});
        Price -> Price
    end.

table_value(Temp, Vector, Name) ->
    entso_tables:value(Temp, Vector, Name).

parse_float(Value) ->
    case string:to_float(Value) of
        {Float, []} -> Float;
        {error, no_float} ->
            {Int, []} = string:to_integer(Value),
            Int * 1.0
    end.

getenv(Name, Default) ->
    case os:getenv(Name) of
        false -> Default;
        "" -> Default;
        Value -> Value
    end.
