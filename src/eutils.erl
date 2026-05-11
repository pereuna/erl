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
    compute_delay_to_next_quarter_ms/0,
    compute_delay_to_next_hour_ms/0,
    compute_delay_to_next_daily_run_ms/0
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
