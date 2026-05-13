%% quarter_worker.erl
%% Vartin välein ajettava koordinaattori: trig GPIO-ohjaus ja ENTSO-E-tarkistus.
-module(quarter_worker).
-behaviour(gen_server).
-export([start_link/0, do_work/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% API: voidaan kutsua myös käsin tarvittaessa.
do_work() ->
    gen_server:cast(?MODULE, do_work).

%% gen_server callbacks
init([]) ->
    Ref = schedule_quarter_work(),
    {ok, #{entso_quarter => entso_quarter:init_state(), timer_ref => Ref}}.

handle_info(fire_quarter_work, State) ->
    do_work(),
    Ref = schedule_quarter_work(),
    {noreply, State#{timer_ref => Ref}};

handle_info(_Info, State) ->
    {noreply, State}.

handle_cast(do_work, State) ->
    TrigResult = trig:do_work(),
    EntsoState0 = maps:get(entso_quarter, State, entso_quarter:init_state()),
    EntsoState = entso_quarter:do_work(EntsoState0),
    {noreply, State#{trig_result => TrigResult, entso_quarter => EntsoState}};

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_call(_Req, _From, State) ->
    {reply, ok, State}.

terminate(_Reason, State) ->
    cancel_timer(maps:get(timer_ref, State, undefined)),
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

schedule_quarter_work() ->
    erlang:send_after(eutils:compute_delay_to_next_quarter_ms(), self(), fire_quarter_work).

cancel_timer(undefined) ->
    ok;
cancel_timer(Ref) ->
    erlang:cancel_timer(Ref),
    ok.
