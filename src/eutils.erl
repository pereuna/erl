%%
%% apufunktioita
%%
-module(eutils).
-export([
    tomorrow_date/0,
    ymd_to_date/1,
    today_utc_string/0,
    tomorrow_utc_string/0,
    local_hour/0,
    fetch_days/2,
    compute_delay_to_next_quarter_ms/0,
    compute_delay_to_next_hour_ms/0,
    compute_delay_to_next_daily_run_ms/0,
    normalize_utc/1,
    utc_to_epoch/1,
    utc_to_epoch_safe/1,
    epoch_to_utc/1,
    parse_float/1,
    xpath_string/2,
    log/3,
    timestamp/0
]).

tomorrow_date() ->
    calendar:gregorian_days_to_date(
        calendar:date_to_gregorian_days(date()) + 1
    ).

today_utc_string() ->
    {Date, _Time} = calendar:universal_time(),
    date_to_string(Date).

tomorrow_utc_string() ->
    {Date, _Time} = calendar:universal_time(),
    Tomorrow = calendar:gregorian_days_to_date(calendar:date_to_gregorian_days(Date) + 1),
    date_to_string(Tomorrow).

local_hour() ->
    {_Date, {Hour, _Minute, _Second}} = calendar:local_time(),
    Hour.

fetch_days(TodayUtc, HourLocal) when HourLocal >= 15 ->
    [TodayUtc, tomorrow_utc_string()];
fetch_days(TodayUtc, _HourLocal) ->
    [TodayUtc].

compute_delay_to_next_quarter_ms() ->
    compute_delay_to_next_period_ms(15 * 60 * 1000).

compute_delay_to_next_hour_ms() ->
    compute_delay_to_next_period_ms(60 * 60 * 1000).

compute_delay_to_next_period_ms(PeriodMs) ->
    Rem = erlang:system_time(millisecond) rem PeriodMs,
    case Rem of
        0 -> 0;
        X -> PeriodMs - X
    end.

compute_delay_to_next_daily_run_ms() ->
    compute_delay_to_next_daily_run_ms(21, 41).

compute_delay_to_next_daily_run_ms(TargetHour, TargetMinute) ->
    {Date, {Hour, Minute, Second}} = calendar:local_time(),
    NowSeconds = calendar:datetime_to_gregorian_seconds({Date, {Hour, Minute, Second}}),
    TargetSeconds0 = calendar:datetime_to_gregorian_seconds({Date, {TargetHour, TargetMinute, 0}}),
    TargetSeconds = case TargetSeconds0 > NowSeconds of
        true -> TargetSeconds0;
        false -> TargetSeconds0 + 24 * 60 * 60
    end,
    (TargetSeconds - NowSeconds) * 1000.

ymd_to_date(S) ->
    %% "YYYY-MM-DD" -> {YYYY,MM,DD}
    [YS, MS, DS] = string:split(S, "-", all),
    {list_to_integer(YS), list_to_integer(MS), list_to_integer(DS)}.

date_to_string({Y, M, D}) ->
    lists:flatten(io_lib:format("~4..0B-~2..0B-~2..0B", [Y, M, D])).

normalize_utc(Time) ->
    S = string:trim(Time),
    case {length(S), lists:suffix("Z", S)} of
        {17, true} -> lists:sublist(S, 16) ++ ":00Z";
        {20, true} -> S;
        _ -> error({invalid_utc_time, Time})
    end.

utc_to_epoch_safe(Time) ->
    try {ok, utc_to_epoch(normalize_utc(Time))}
    catch _:_ -> error
    end.

utc_to_epoch(Utc) ->
    [Date, TimeZ] = string:split(Utc, "T"),
    Time = string:trim(TimeZ, trailing, "Z"),
    [YS, MS, DS] = string:split(Date, "-", all),
    [HS, MinS, SS] = string:split(Time, ":", all),
    DateTime = {
        {list_to_integer(YS), list_to_integer(MS), list_to_integer(DS)},
        {list_to_integer(HS), list_to_integer(MinS), list_to_integer(SS)}
    },
    calendar:datetime_to_gregorian_seconds(DateTime) - unix_epoch_gregorian_seconds().

epoch_to_utc(Epoch) ->
    {{Y, M, D}, {H, Min, S}} = calendar:gregorian_seconds_to_datetime(Epoch + unix_epoch_gregorian_seconds()),
    lists:flatten(io_lib:format("~4..0B-~2..0B-~2..0BT~2..0B:~2..0B:~2..0BZ", [Y, M, D, H, Min, S])).

unix_epoch_gregorian_seconds() ->
    calendar:datetime_to_gregorian_seconds({{1970, 1, 1}, {0, 0, 0}}).

parse_float(Value) ->
    case string:to_float(Value) of
        {Float, []} -> Float;
        {error, no_float} ->
            {Int, []} = string:to_integer(Value),
            Int * 1.0
    end.

xpath_string(Path, Node) ->
    {_, _, Value} = xmerl_xpath:string("string(" ++ Path ++ ")", Node),
    unicode:characters_to_list(Value).

log(LogFile, Format, Args) ->
    Line = io_lib:format("~s " ++ Format ++ "~n", [timestamp() | Args]),
    _ = filelib:ensure_dir(LogFile),
    _ = file:write_file(LogFile, Line, [append]),
    logger:info(Format, Args),
    ok.

timestamp() ->
    {{Y, M, D}, {H, Min, S}} = calendar:local_time(),
    lists:flatten(io_lib:format("~4..0B-~2..0B-~2..0B ~2..0B:~2..0B:~2..0B", [Y, M, D, H, Min, S])).
