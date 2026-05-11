%% scheduler.erl
-module(scheduler).
-behaviour(gen_server).
-export([start_link/0, compute_delay_to_next_quarter_ms/0, compute_delay_to_next_daily_run_ms/0]).
-export([init/1, handle_info/2, handle_call/3, handle_cast/2, terminate/2, code_change/3]).

%%% Public API %%%
start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%%% gen_server callbacks %%%
init([]) ->
    QuarterRef = schedule_quarter_work(),
    DailyRunRef = schedule_daily_run_plan(),
    {ok, #{quarter_timer_ref => QuarterRef, daily_run_timer_ref => DailyRunRef}}.

handle_info(fire_quarter_work, State) ->
    %% Käynnistä varttikohtainen ENTSO-tarkistus/hakutyö (asynkronisesti)
    catch quarter_worker:do_work(),

    %% Aseta seuraava varttiajastus uudestaan laskemalla tarkasti
    Ref = schedule_quarter_work(),
    {noreply, State#{quarter_timer_ref => Ref}};

handle_info(fire_daily_run_plan, State) ->
    %% Vanhan crontab-esimerkin mukainen ilta-ajo seuraavan päivän run.txt:lle.
    catch quarter_worker:do_run_plan(),

    %% Aseta seuraava päiväajo uudestaan laskemalla tarkasti
    Ref = schedule_daily_run_plan(),
    {noreply, State#{daily_run_timer_ref => Ref}};

handle_info(_Other, State) ->
    {noreply, State}.

handle_call(_Req, _From, State) ->
    {reply, ok, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

terminate(_Reason, State) ->
    cancel_timer(maps:get(quarter_timer_ref, State, undefined)),
    cancel_timer(maps:get(daily_run_timer_ref, State, undefined)),
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%% ------------------------------------------------------------------
%%% Laskee montako millisekuntia odotetaan seuraavaan 15-minuutin "kvartaaliin".
%%% Käyttää epoch-sekunteja:
%%% Palauttaa millisekunteina.
%%% ------------------------------------------------------------------

compute_delay_to_next_quarter_ms() ->
    Qms = 15 * 60 * 1000, %% 15 min millisekunteina (900000)
    Rem = erlang:system_time(millisecond) rem Qms,
    case Rem of
        0 -> 0;       %% täsmälleen kvartaalihetkellä -> aja heti
        X -> Qms - X  %% muutoin: aika seuraavaan kvartaaliin
    end.


schedule_quarter_work() ->
    erlang:send_after(compute_delay_to_next_quarter_ms(), self(), fire_quarter_work).

schedule_daily_run_plan() ->
    erlang:send_after(compute_delay_to_next_daily_run_ms(), self(), fire_daily_run_plan).

cancel_timer(undefined) ->
    ok;
cancel_timer(Ref) ->
    erlang:cancel_timer(Ref),
    ok.

compute_delay_to_next_daily_run_ms() ->
    compute_delay_to_next_daily_run_ms(21, 41).

compute_delay_to_next_daily_run_ms(TargetHour, TargetMinute) ->
    {Date, {Hour, Minute, Second}} = calendar:local_time(),
    NowSeconds = calendar:datetime_to_gregorian_seconds({Date, {Hour, Minute, Second}}),
    TargetSeconds0 = calendar:datetime_to_gregorian_seconds({Date, {TargetHour, TargetMinute, 0}}),
    TargetSeconds = case TargetSeconds0 > NowSeconds of
        true -> TargetSeconds0;
        false -> TargetSeconds0 + 24 * 60 * 60
    end,
    (TargetSeconds - NowSeconds) * 1000.
