%% entso_quarter.erl
%% ENTSO-E:n varttitarkistus, jonka periodinen ajo on quarter_workerissa.
-module(entso_quarter).

-export([init_state/0, do_work/1]).

-record(entso_xml, {day, file, start = [], 'end' = []}).

init_state() ->
    #{entso_xml => #{}}.

%% Tarkistaa ENTSO-E XML:t vartin välein. Jos päivän entso.xml on jo olemassa
%% ja kelvollinen, kurl:fetch_day/1 käyttää sitä eikä tee turhaa HTTP-hakua.
do_work(State) ->
    TodayUtc = eutils:today_utc_string(),
    FetchDays = eutils:fetch_days(TodayUtc, eutils:local_hour()),
    logger:info("entso quarter ~p fetch_days:~p", [calendar:local_time(), FetchDays]),
    lists:foldl(fun fetch_and_store/2, State, FetchDays).

fetch_and_store(Day, State) ->
    case kurl:fetch_day(Day) of
        {ok, Metadata} ->
            EntsoXml = #entso_xml{
                day = Day,
                file = maps:get(file, Metadata),
                start = maps:get(start, Metadata, []),
                'end' = maps:get('end', Metadata, [])
            },
            EntsoByDay0 = maps:get(entso_xml, State, #{}),
            State#{entso_xml => EntsoByDay0#{Day => EntsoXml}};
        {error, Reason} ->
            logger:error("get_entso_xml: day=~s failed: ~p", [Day, Reason]),
            State
    end.
