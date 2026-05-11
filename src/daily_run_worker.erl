%% daily_run_worker.erl
-module(daily_run_worker).
-behaviour(gen_server).
-export([start_link/0, do_work/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% Päivittäinen run.txt-suunnittelu seuraavaa päivää varten.
do_work() ->
    gen_server:cast(?MODULE, do_work).

init([]) ->
    Ref = schedule_daily_run_plan(),
    {ok, #{timer_ref => Ref}}.

handle_info(fire_daily_run_plan, State) ->
    do_work(),
    Ref = schedule_daily_run_plan(),
    {noreply, State#{timer_ref => Ref}};

handle_info(_Info, State) ->
    {noreply, State}.

handle_cast(do_work, State) ->
    Day = eutils:tomorrow_utc_string(),
    Result = update_run_plan(Day),
    logger:info("daily run plan result: ~p", [Result]),
    {noreply, State#{last_run_plan_day => Day, run_results => [Result]}};

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

schedule_daily_run_plan() ->
    erlang:send_after(eutils:compute_delay_to_next_daily_run_ms(), self(), fire_daily_run_plan).
