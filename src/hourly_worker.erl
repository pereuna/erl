%% hourly_worker.erl
%% Hakee FMI-säätiedot kerran tunnissa aina uusimman ennusteen mukaan.
-module(hourly_worker).
-behaviour(gen_server).

-export([start_link/0, do_work/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-record(entso_xml, {day, file, start = [], 'end' = []}).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

do_work() ->
    gen_server:cast(?MODULE, do_work).

init([]) ->
    Ref = schedule_hourly_work(),
    {ok, #{timer_ref => Ref, fmi_results => []}}.

handle_info(fire_hourly_work, State) ->
    do_work(),
    Ref = schedule_hourly_work(),
    {noreply, State#{timer_ref => Ref}};

handle_info(_Info, State) ->
    {noreply, State}.

handle_cast(do_work, State) ->
    TodayUtc = eutils:today_utc_string(),
    FetchDays = fetch_days(TodayUtc, eutils:local_hour()),
    logger:info("hourly fmi fetch_days:~p", [FetchDays]),
    EntsoXmls = fetch_entso_days(FetchDays),
    Specs = fmi_day_specs(EntsoXmls),
    Results = fetch_fmi(Specs),
    logger:info("hourly fmi update results: ~p", [Results]),
    {noreply, State#{entso_xml => EntsoXmls, fmi_results => Results}};

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_call(_Req, _From, State) ->
    {reply, ok, State}.

terminate(_Reason, State) ->
    case maps:get(timer_ref, State, undefined) of
        undefined -> ok;
        Ref -> erlang:cancel_timer(Ref), ok
    end.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

fetch_days(TodayUtc, HourLocal) when HourLocal >= 15 ->
    [TodayUtc, eutils:tomorrow_utc_string()];
fetch_days(TodayUtc, _HourLocal) ->
    [TodayUtc].

fetch_entso_days(FetchDays) ->
    lists:filtermap(fun fetch_entso_day/1, FetchDays).

fetch_entso_day(Day) ->
    case kurl:fetch_day(Day) of
        {ok, Metadata} ->
            {true, #entso_xml{
                day = Day,
                file = maps:get(file, Metadata),
                start = maps:get(start, Metadata, []),
                'end' = maps:get('end', Metadata, [])
            }};
        {error, Reason} ->
            logger:error("hourly fmi entso check failed: day=~s reason=~p", [Day, Reason]),
            false
    end.

fmi_day_specs(EntsoXmls) ->
    lists:filtermap(
        fun
            (#entso_xml{day = Day, start = [Start | _], 'end' = [End | _]}) ->
                {true, {Day, Start, End}};
            (_) ->
                false
        end,
        EntsoXmls).

fetch_fmi([]) ->
    [];
fetch_fmi(Specs) ->
    %% FMI-haussa ei ole omaa due/cache-tarkistusta: uusin havainto/ennuste haetaan joka tunti.
    fmi:fetch_days(Specs).

schedule_hourly_work() ->
    erlang:send_after(eutils:compute_delay_to_next_hour_ms(), self(), fire_hourly_work).
