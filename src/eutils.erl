%%
%% apufunktioita
%%
-module(eutils).
-export([tomorrow_date/0, ymd_to_date/1]).

tomorrow_date() ->
    calendar:gregorian_days_to_date(
        calendar:date_to_gregorian_days(date()) + 1
    ).

ymd_to_date(S) ->
    %% "YYYY-MM-DD" -> {YYYY,MM,DD}
    [YS, MS, DS] = string:split(S, "-", all),
    {list_to_integer(YS), list_to_integer(MS), list_to_integer(DS)}.
