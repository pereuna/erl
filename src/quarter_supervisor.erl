%% quarter_supervisor.erl
-module(quarter_supervisor).
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
        {daily_run_worker, {daily_run_worker, start_link, []},
         permanent, 5000, worker, [daily_run_worker]}
    ],
    {ok, {{one_for_one, 5, 10}, Children}}.
