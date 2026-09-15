-module(entso_run_tests).

-include_lib("eunit/include/eunit.hrl").

space_heat_demand_at_freezing_test() ->
    ?assertEqual(6.0, entso_run:space_heat_demand_kw(0)).

space_heat_demand_in_current_conditions_test() ->
    ?assert(abs(3.6 - entso_run:space_heat_demand_kw(12)) < 1.0e-12).

space_heat_demand_at_warm_weather_cutoff_test() ->
    ?assertEqual(0.0, entso_run:space_heat_demand_kw(30)).

space_heat_demand_for_example_day_test() ->
    AverageOutdoorTemp = 14.333333333333334,
    ExpectedDailyKwh = 75.2,
    ActualDailyKwh =
        entso_run:space_heat_demand_kw(AverageOutdoorTemp) * 24.0,
    ?assert(abs(ExpectedDailyKwh - ActualDailyKwh) < 1.0e-12).
