%% quarter_worker.erl
-module(quarter_worker).
-behaviour(gen_server).
-export([start_link/0, do_work/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-record(entso_xml, {day, file, start = [], 'end' = []}).

-define(FMI_INTERVAL_SECONDS, 60 * 60).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% API: kutsutaan schedulerista
do_work() ->
    gen_server:cast(?MODULE, do_work).

%% gen_server callbacks
init([]) ->
    {ok, #{entso_xml => #{}, last_fmi_update => undefined}}.

handle_cast(do_work, State) ->
    TodayUtc = eutils:today_utc_string(),
    FetchDays = fetch_days(TodayUtc, eutils:local_hour()),
    logger:info("qw ~p fetch_days:~p", [calendar:local_time(), FetchDays]),
    State1 = lists:foldl(fun fetch_and_store/2, State, FetchDays),
    NewState = update_fmi_if_due(State1, FetchDays),
    {noreply, NewState};

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

update_fmi_if_due(State, FetchDays) ->
    Now = erlang:system_time(second),
    LastUpdate = maps:get(last_fmi_update, State, undefined),
    case fmi_update_due(Now, LastUpdate) of
        true ->
            update_fmi(State, FetchDays, Now);
        false ->
            State
    end.

update_fmi(State, FetchDays, Now) ->
    Specs = fmi_day_specs(State, FetchDays),
    case Specs of
        [] ->
            State;
        _ ->
            Results = fmi:fetch_days(Specs),
            logger:info("fmi update results: ~p", [Results]),
            State#{last_fmi_update => Now, fmi_results => Results}
    end.

fmi_day_specs(State, FetchDays) ->
    EntsoByDay = maps:get(entso_xml, State, #{}),
    lists:filtermap(
        fun(Day) ->
            case maps:get(Day, EntsoByDay, undefined) of
                #entso_xml{start = [Start | _], 'end' = [End | _]} ->
                    {true, {Day, Start, End}};
                _ ->
                    false
            end
        end,
        FetchDays).

fmi_update_due(_Now, undefined) ->
    true;
fmi_update_due(Now, LastUpdate) ->
    Now - LastUpdate >= ?FMI_INTERVAL_SECONDS.
