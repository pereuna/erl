%% entso_run.erl
%% Laskee vanhan /rc/trilogy.rc + trilogy-awk -ketjun tuottaman run.txt-suunnitelman.
-module(entso_run).

-export([plan_day/1, plan_day/2, plan_day/4, control_plan/1, action_for_time/1]).

-define(DEFAULT_VAR_DIR, "/var/www/htdocs/jedi.ydns.eu/var").
-define(VVARAAJA, 2.0).
-define(U, 1.17).

plan_day(Day) ->
    VarDir = getenv("QUARTER_VAR_DIR", ?DEFAULT_VAR_DIR),
    DayDir = filename:join([VarDir | string:split(Day, "-", all)]),
    plan_day_files(
        filename:join(DayDir, "prices.txt"),
        filename:join(DayDir, "temps.txt"),
        filename:join(DayDir, "run.txt")
    ).

plan_day(PricesFile, TempsFile) ->
    DayDir = filename:dirname(TempsFile),
    plan_day_files(
        PricesFile,
        TempsFile,
        filename:join(DayDir, "run.txt")
    ).

plan_day(PricesFile, TempsFile, P55, COP55) ->
    DayDir = filename:dirname(TempsFile),
    plan_day_files(
        PricesFile,
        TempsFile,
        filename:join(DayDir, "run.txt"),
        P55,
        COP55
    ).

action_for_time(TimeUtc) ->
    [Day, _Time] = string:split(TimeUtc, "T"),
    VarDir = getenv("QUARTER_VAR_DIR", ?DEFAULT_VAR_DIR),
    DayDir = filename:join([VarDir | string:split(Day, "-", all)]),
    case build_plan_files(
        filename:join(DayDir, "prices.txt"),
        filename:join(DayDir, "temps.txt"),
        filename:join(DayDir, "run.txt"),
        entso_tables:p55(),
        entso_tables:cop55()
    ) of
        {ok, _Metadata, Plan} -> {ok, maps:get(TimeUtc, Plan, normal)};
        {error, Reason} -> {error, Reason}
    end.

plan_day_files(PricesFile, TempsFile, RunLogFile) ->
    plan_day_files(PricesFile, TempsFile, RunLogFile, entso_tables:p55(), entso_tables:cop55()).

plan_day_files(PricesFile, TempsFile, RunLogFile, P55, COP55) ->
    case build_plan_files(PricesFile, TempsFile, RunLogFile, P55, COP55) of
        {ok, Metadata, _Plan} -> {ok, Metadata};
        {error, Reason} -> {error, Reason}
    end.

build_plan_files(PricesFile, TempsFile, RunLogFile, P55, COP55) ->
    try
        Prices = prices(PricesFile),
        Temps = temps(TempsFile),
        Rows = rows(Temps, Prices, P55, COP55),
        Plan = control_plan(Rows),
        RunLog = run_log(Plan),
        ok = filelib:ensure_dir(RunLogFile),
        ok = file:write_file(RunLogFile, RunLog),
        Metadata = #{run => RunLogFile, rows => length(Rows), actions => maps:size(Plan)},
        {ok, Metadata, Plan}
    catch
        Class:Reason ->
            {error, {Class, Reason}}
    end.

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

control_plan(Rows) ->
    Cheapest = lists:sort(fun cheaper_first/2, Rows),
    Expensive = lists:sort(fun pricier_first/2, Rows),
    Charge = selected_times(Cheapest, pvarasto),
    Discharge = selected_times(Expensive, ptarve),
    %% Jos sama vartti päätyy molempiin listoihin, lataus voittaa kuten vanhassa
    %% shell-logiikassa, joka tarkisti L-merkinnän ennen P-merkintää.
    maps:merge(
        maps:from_list([{Time, discharge} || Time <- Discharge]),
        maps:from_list([{Time, charge} || Time <- Charge])
    ).

run_log(Plan) ->
    Lines = [io_lib:format("~s\t~s~n", [Time, action_label(Action)]) ||
        {Time, Action} <- lists:sort(maps:to_list(Plan))],
    unicode:characters_to_binary(Lines).

action_label(charge) -> "L";
action_label(discharge) -> "P".

cheaper_first(A, B) ->
    sort_key(A) < sort_key(B).

pricier_first(A, B) ->
    sort_key(A) > sort_key(B).

sort_key(Row) ->
    {maps:get(rhinta, Row), maps:get(time, Row)}.

selected_times(Rows, SumKey) ->
    selected_times(Rows, SumKey, 0.0, []).

selected_times([], _SumKey, _Acc, Out) ->
    lists:reverse(Out);
selected_times([Row | Rest], SumKey, Acc0, Out) ->
    Acc = Acc0 + maps:get(SumKey, Row),
    Out1 = [maps:get(time, Row) | Out],
    case Acc > maps:get(udiff, Row) of
        true -> lists:reverse(Out1);
        false -> selected_times(Rest, SumKey, Acc, Out1)
    end.

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
    {Time, eutils:parse_float(PriceS)}.

price_at(Time, Prices) ->
    case maps:get(Time, Prices, undefined) of
        undefined -> error({missing_price, Time});
        Price -> Price
    end.

table_value(Temp, Vector, Name) ->
    entso_tables:value(Temp, Vector, Name).

getenv(Name, Default) ->
    case os:getenv(Name) of
        false -> Default;
        "" -> Default;
        Value -> Value
    end.
