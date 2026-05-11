%% quarter_worker.erl
-module(quarter_worker).
-behaviour(gen_server).
-export([start_link/0, do_work/0, do_run_plan/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-record(entso_xml, {day, file, start = [], 'end' = []}).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% API: kutsutaan schedulerista
do_work() ->
    gen_server:cast(?MODULE, do_work).

%% Päivittäinen run.txt-suunnittelu seuraavaa päivää varten.
do_run_plan() ->
    gen_server:cast(?MODULE, do_run_plan).

%% gen_server callbacks
init([]) ->
    {ok, #{entso_xml => #{}}}.

handle_cast(do_work, State) ->
    TodayUtc = eutils:today_utc_string(),
    FetchDays = fetch_days(TodayUtc, eutils:local_hour()),
    logger:info("qw ~p fetch_days:~p", [calendar:local_time(), FetchDays]),
    NewState = lists:foldl(fun fetch_and_store/2, State, FetchDays),
    {noreply, NewState};

handle_cast(do_run_plan, State) ->
    Day = eutils:tomorrow_utc_string(),
    Result = update_run_plan(Day),
    logger:info("daily run plan result: ~p", [Result]),
    {noreply, State#{last_run_plan_day => Day, run_results => [Result]}};

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_call(_Req, _From, State) ->
    {reply, ok, State}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

fetch_days(TodayUtc, HourLocal) when HourLocal >= 15 ->
    [TodayUtc, eutils:tomorrow_utc_string()];
fetch_days(TodayUtc, _HourLocal) ->
    [TodayUtc].

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


update_run_plan(Day) ->
    try entso_run:plan_day(Day) of
        Result ->
            {Day, Result}
    catch
        Class:Reason:Stacktrace ->
            logger:error("run plan failed: day=~s ~p:~p", [Day, Class, Reason]),
            logger:debug("run plan stacktrace: ~p", [Stacktrace]),
            {Day, {error, {Class, Reason}}}
    end.
