%% entso_run.erl
%% Laskee vanhan /rc/trilogy.rc + trilogy-awk -ketjun tuottaman run.txt-suunnitelman.
-module(entso_run).

-export([plan_day/1, control_plan/1, action_for_time/1]).

-define(DEFAULT_VAR_DIR, "/var/www/htdocs/jedi.ydns.eu/var").
-define(VVARAAJA, 2.0).
-define(U, 1.17).

plan_day(Day) ->
    DayDir = day_dir(Day),
    PricesFile = filename:join(DayDir, "prices.txt"),
    TempsFile = filename:join(DayDir, "temps.txt"),
    RunLogFile = filename:join(DayDir, "run.txt"),
    case build_plan_files(PricesFile, TempsFile, RunLogFile) of
        {ok, Metadata, _Plan} -> {ok, Metadata};
        {error, Reason} -> {error, Reason}
    end.

action_for_time(TimeUtc) ->
    [Day, _Time] = string:split(TimeUtc, "T"),
    DayDir = day_dir(Day),
    case build_plan_files(
        filename:join(DayDir, "prices.txt"),
        filename:join(DayDir, "temps.txt"),
        filename:join(DayDir, "run.txt")
    ) of
        {ok, _Metadata, Plan} -> {ok, maps:get(TimeUtc, Plan, normal)};
        {error, Reason} -> {error, Reason}
    end.

build_plan_files(PricesFile, TempsFile, RunLogFile) ->
    try
        Prices = prices(PricesFile),
        Temps = temps(TempsFile),
        Rows = rows(Temps, Prices),
        Plan = control_plan(Rows),
        RunLog = run_log(Plan),
        ok = filelib:ensure_dir(RunLogFile),
        ok = file:write_file(RunLogFile, RunLog),
        DailyNeed = daily_heat_need(Rows),
        NormalHours = required_normal_hours(Rows, DailyNeed),
        Metadata = #{
            run => RunLogFile,
            rows => length(Rows),
            actions => maps:size(Plan),
            daily_heat_need_kwh => DailyNeed,
            required_normal_hours => NormalHours
        },
        {ok, Metadata, Plan}
    catch
        Class:Reason ->
            {error, {Class, Reason}}
    end.

rows(Temps, Prices) ->
    [row(Time, Temp, price_at(Time, Prices)) || {Time, Temp} <- Temps].

row(Time, Temp, Price) ->
    SupplyTemp = entso_tables:target_supply_temp(Temp),
    PValue = entso_tables:p(Temp, SupplyTemp),
    COPValue = entso_tables:cop(Temp, SupplyTemp),
    Rhinta = ((Price + 63.3) * 1.24) / COPValue,
    Ptarve = -0.2 * Temp + 6,
    Pvarasto = PValue - Ptarve,
    Tdiff = 55 - SupplyTemp,
    Udiff = Tdiff * ?VVARAAJA * ?U,
    #{time => Time, temp => Temp, price => Price, rhinta => Rhinta,
      ptarve => Ptarve, pvarasto => Pvarasto, udiff => Udiff,
      normal_energy => PValue * 0.25}.

control_plan(Rows) ->
    DailyNeed = daily_heat_need(Rows),
    Cheapest = lists:sort(fun cheaper_first/2, Rows),
    {NormalTimes, _Delivered} = select_normal_times(Cheapest, DailyNeed),
    NormalSet = maps:from_list([{Time, true} || Time <- NormalTimes]),
    DischargeTimes = [maps:get(time, Row) || Row <- Rows, not maps:is_key(maps:get(time, Row), NormalSet)],
    maps:from_list([{Time, discharge} || Time <- DischargeTimes]).

run_log(Plan) ->
    Lines = [io_lib:format("~s\t~s~n", [Time, action_label(Action)]) ||
        {Time, Action} <- lists:sort(maps:to_list(Plan))],
    unicode:characters_to_binary(Lines).

action_label(discharge) -> "P".

cheaper_first(A, B) ->
    sort_key(A) < sort_key(B).

sort_key(Row) ->
    {maps:get(rhinta, Row), maps:get(time, Row)}.

daily_heat_need(Rows) ->
    lists:sum([maps:get(normal_energy, Row) || Row <- Rows]).

required_normal_hours([], _DailyNeed) ->
    0.0;
required_normal_hours(Rows, DailyNeed) ->
    AvgNormalPower = lists:sum([maps:get(pvarasto, Row) + maps:get(ptarve, Row) || Row <- Rows]) / length(Rows),
    case AvgNormalPower =< 0.0 of
        true -> 24.0;
        false -> DailyNeed / AvgNormalPower
    end.

select_normal_times(Rows, Need) ->
    select_normal_times(Rows, Need, 0.0, []).

select_normal_times([], _Need, _Acc, Out) ->
    lists:reverse(Out);
select_normal_times([Row | Rest], Need, Acc0, Out) ->
    Acc = Acc0 + maps:get(normal_energy, Row),
    Out1 = [maps:get(time, Row) | Out],
    case Acc >= Need of
        true -> lists:reverse(Out1);
        false -> select_normal_times(Rest, Need, Acc, Out1)
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

day_dir(Day) ->
    filename:join([?DEFAULT_VAR_DIR | string:split(Day, "-", all)]).
