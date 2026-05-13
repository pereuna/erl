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
    Start = string:trim(eutils:xpath_string(".//*[local-name()='timeInterval']/*[local-name()='start']", Period)),
    End = string:trim(eutils:xpath_string(".//*[local-name()='timeInterval']/*[local-name()='end']", Period)),
    StartEpoch = eutils:utc_to_epoch(eutils:normalize_utc(Start)),
    EndEpoch = eutils:utc_to_epoch(eutils:normalize_utc(End)),
    PointNodes = xmerl_xpath:string("*[local-name()='Point']", Period),
    Points = lists:sort([{pos_int(Node), price_float(Node)} || Node <- PointNodes]),
    Count = max(0, (EndEpoch - StartEpoch) div ?QUARTSEC),
    Filled = fill_gaps(Points, 1, Count, 0.0),
    [{eutils:epoch_to_utc(StartEpoch + (Pos - 1) * ?QUARTSEC), Price} || {Pos, Price} <- Filled].

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
    {Pos, []} = string:to_integer(string:trim(eutils:xpath_string("*[local-name()='position']", Node))),
    Pos.

price_float(Node) ->
    eutils:parse_float(string:trim(eutils:xpath_string("*[local-name()='price.amount']", Node))).
