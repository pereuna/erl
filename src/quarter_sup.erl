%% quarter_sup.erl
-module(quarter_sup).
-behaviour(supervisor).
-export([start_link/0, init/1]).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    Children = [
        {quarter_worker, {quarter_worker, start_link, []},
         permanent, 5000, worker, [quarter_worker]},
        {hourly_worker, {hourly_worker, start_link, []},
         permanent, 5000, worker, [hourly_worker]},
        {quarter_scheduler, {quarter_scheduler, start_link, []},
         permanent, 5000, worker, [quarter_scheduler]},
        {worker, {worker, start_link, []},
         permanent, 5000, worker, [worker]}
    ],
    {ok, {{one_for_one, 5, 10}, Children}}.
