%% file: worker.erl
-module(worker).
-behaviour(gen_server).

%% API
-export([start_link/0, send_msg/1]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

%%%===================================================================
%%% API
%%%===================================================================

start_link() ->
    gen_server:start_link({local, worker}, ?MODULE, [], []).

send_msg(Msg) ->
    gen_server:cast(worker, {msg, Msg}).

%%%===================================================================
%%% Callbacks
%%%===================================================================

init([]) ->
    logger:info("Worker started on ~p", [node()]),
    {ok, []}.

handle_call(_Request, _From, State) ->
    {reply, ok, State}.

handle_cast({msg, Msg}, State) ->
    logger:info("Worker received message: ~p", [Msg]),
    {noreply, State};

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.
