-module(xml_parse).
-export([parse_file/1, write_prices/1, write_prices/2]).

-include_lib("xmerl/include/xmerl.hrl").

-define(QUARTSEC, 900).  %% 15 minutes in seconds

%% Parse a day-directory ENTSO XML file, normally YYYY/MM/DD/entso.xml, into
%% the same logical rows that the old do_entso step wrote to prices.txt: UTC
%% timestamp and filled quarter-hour price.
parse_file(File) ->
    {Doc, _} = xmerl_scan:file(File),
    Periods = xmerl_xpath:string("//*[local-name()='Period']", Doc),
    lists:append([period_prices(Period) || Period <- Periods]).

%% Write prices.txt next to the given day-directory entso.xml.
write_prices(EntsoXml) ->
    write_prices(EntsoXml, filename:join(filename:dirname(EntsoXml), "prices.txt")).

write_prices(EntsoXml, PricesFile) ->
    Rows = parse_file(EntsoXml),
    ok = file:write_file(PricesFile, prices_txt(Rows)),
    {ok, #{prices => PricesFile, rows => length(Rows)}}.

period_prices(Period) ->
    Start = xpath_string(".//*[local-name()='timeInterval']/*[local-name()='start']", Period),
    End = xpath_string(".//*[local-name()='timeInterval']/*[local-name()='end']", Period),
    StartEpoch = utc_to_epoch(normalize_utc(Start)),
    EndEpoch = utc_to_epoch(normalize_utc(End)),
    PointNodes = xmerl_xpath:string("*[local-name()='Point']", Period),
    Points = lists:sort([{pos_int(Node), price_float(Node)} || Node <- PointNodes]),
    Count = max(0, (EndEpoch - StartEpoch) div ?QUARTSEC),
    Filled = fill_gaps(Points, 1, Count, 0.0),
    [{epoch_to_utc(StartEpoch + (Pos - 1) * ?QUARTSEC), Price} || {Pos, Price} <- Filled].

fill_gaps(_Points, N, Count, _LastPrice) when N > Count ->
    [];
fill_gaps([{N, Price} | Rest], N, Count, _LastPrice) ->
    [{N, Price} | fill_gaps(Rest, N + 1, Count, Price)];
fill_gaps([{Pos, _Price} | _] = Points, N, Count, LastPrice) when Pos > N ->
    [{N, LastPrice} | fill_gaps(Points, N + 1, Count, LastPrice)];
fill_gaps([{_Pos, Price} | Rest], N, Count, _LastPrice) ->
    fill_gaps(Rest, N, Count, Price);
fill_gaps([], N, Count, LastPrice) ->
    [{N, LastPrice} | fill_gaps([], N + 1, Count, LastPrice)].

prices_txt(Rows) ->
    unicode:characters_to_binary([io_lib:format("~s ~.2f~n", [Time, Price]) || {Time, Price} <- Rows]).

pos_int(Node) ->
    {Pos, []} = string:to_integer(xpath_string("*[local-name()='position']", Node)),
    Pos.

price_float(Node) ->
    parse_float(xpath_string("*[local-name()='price.amount']", Node)).

xpath_string(Path, Node) ->
    {_, _, Value} = xmerl_xpath:string("string(" ++ Path ++ ")", Node),
    string:trim(unicode:characters_to_list(Value)).

parse_float(Value) ->
    case string:to_float(Value) of
        {Float, []} -> Float;
        {error, no_float} ->
            {Int, []} = string:to_integer(Value),
            Int * 1.0
    end.

normalize_utc(Time) ->
    S = string:trim(Time),
    case {length(S), lists:suffix("Z", S)} of
        {17, true} -> lists:sublist(S, 16) ++ ":00Z";
        {20, true} -> S;
        _ -> error({invalid_utc_time, Time})
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
