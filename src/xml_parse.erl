-module(xml_parse).
-export([parse/0]).

-define(QUARTSEC, 900).  %% 15 minutes in seconds

%% parse/0 parses the XML file koe.xml and returns a list of tuples with position and price
%% fill_gaps/1 fills missing positions in the list with previous price value

parse() ->
    {E, _R} = xmerl_scan:file("koe.xml"),
    PointsNodes = xmerl_xpath:string("//*[local-name()='Point']", E),
    Pairs = [{pos_int(Node, "position"), price_float(Node, "price.amount")} || Node <- PointsNodes],
    [Nod] = xmerl_xpath:string(
        "/*[local-name()='Publication_MarketDocument']"
        "//*[local-name()='period.timeInterval']/*[local-name()='start']", E),
    {_, _, Str} = xmerl_xpath:string("string()", Nod),
    Ep = calendar:rfc3339_to_system_time(lists:sublist(Str, length(Str) - 1) ++ ":00+00:00"),
    Pairsf = fill_gaps(Pairs, 1, 0.0),
    [{Ep + (Pos - 1) * ?QUARTSEC, Price} || {Pos, Price} <- Pairsf, Pos =< 96].

fill_gaps(Pairs, N, LastPrice) ->
    case Pairs of
        %% Exact match for this position: keep it
        [{N, Price} | Rest] ->
            [{N, Price} | fill_gaps(Rest, N + 1, Price)];

        %% Missing position: use last known price
        [{_Pos, _Price} | _] = All ->
            [{N, LastPrice} | fill_gaps(All, N + 1, LastPrice)];

        %% End of list
        [] ->
            []
    end.

pos_int(Node, Field) ->
    Lf = lists:flatten(io_lib:format("string(*[local-name()='~s'])", [Field])),
    {_, _, Val} = xmerl_xpath:string(Lf, Node),
    element(1, string:to_integer(Val)).

price_float(Node, Field) ->
    Lf = lists:flatten(io_lib:format("string(*[local-name()='~s'])", [Field])),
    {_, _, Val} = xmerl_xpath:string(Lf, Node),
    element(1, string:to_float(Val ++ ".0")).
