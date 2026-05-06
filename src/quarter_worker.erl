%% quarter_worker.erl
-module(quarter_worker).
-behaviour(gen_server).
-export([start_link/0, do_work/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% API: kutsutaan schedulerista
do_work() ->
    gen_server:cast(?MODULE, do_work).

%% gen_server callbacks
init([]) ->
    {ok, #{}}.

handle_cast(do_work, State) ->
    Day = eutils:tomorrow_date(),
    logger:info("qw ~p day:~p", [calendar:local_time(), Day]),
    {noreply, State};

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
