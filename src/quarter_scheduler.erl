%% quarter_scheduler.erl
-module(quarter_scheduler).
-behaviour(gen_server).
-export([start_link/0, compute_delay_to_next_quarter_ms/0]).
-export([init/1, handle_info/2, handle_call/3, handle_cast/2, terminate/2, code_change/3]).

%%% Public API %%%
start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%%% gen_server callbacks %%%
init([]) ->
    DelayMs = compute_delay_to_next_quarter_ms(),
    Ref = erlang:send_after(DelayMs, self(), fire),
    {ok, #{timer_ref => Ref}}.

handle_info(fire, State) ->
    %% Käynnistä työ (asynkronisesti)
    catch quarter_worker:do_work(),

    %% Aseta seuraava ajastus uudestaan laskemalla tarkasti
    DelayMs = compute_delay_to_next_quarter_ms(),
    Ref = erlang:send_after(DelayMs, self(), fire),
    {noreply, State#{timer_ref => Ref}};

handle_info(_Other, State) ->
    {noreply, State}.

handle_call(_Req, _From, State) ->
    {reply, ok, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

terminate(_Reason, State) ->
    case maps:get(timer_ref, State, undefined) of
        undefined -> ok;
        Ref -> erlang:cancel_timer(Ref)
    end,
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
