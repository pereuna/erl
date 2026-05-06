%%
%% apufunktioita
%%
-module(eutils).
-export([tomorrow_date/0, ymd_to_date/1, today_utc_string/0, tomorrow_utc_string/0, local_hour/0]).

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

ymd_to_date(S) ->
    %% "YYYY-MM-DD" -> {YYYY,MM,DD}
    [YS, MS, DS] = string:split(S, "-", all),
    {list_to_integer(YS), list_to_integer(MS), list_to_integer(DS)}.

date_to_string({Y, M, D}) ->
    lists:flatten(io_lib:format("~4..0B-~2..0B-~2..0B", [Y, M, D])).
