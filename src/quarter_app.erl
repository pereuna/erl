-module(quarter_app).
-behaviour(application).
-export([start/2, stop/1]).

start(_StartType, _StartArgs) ->
    quarter_supervisor:start_link().

stop(_State) ->
    ok.
