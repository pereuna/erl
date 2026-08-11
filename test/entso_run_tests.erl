-module(entso_run_tests).

-include_lib("eunit/include/eunit.hrl").

space_heat_demand_at_design_temperature_test() ->
    ?assertEqual(8.0, entso_run:space_heat_demand_kw(-26)).

space_heat_demand_at_balance_temperature_test() ->
    ?assertEqual(0.0, entso_run:space_heat_demand_kw(17)).

space_heat_demand_above_balance_temperature_test() ->
    ?assertEqual(0.0, entso_run:space_heat_demand_kw(20)).

space_heat_demand_for_example_day_test() ->
    AverageOutdoorTemp = 14.333333333333334,
    ExpectedDailyKwh = 11.906976744186043,
    ActualDailyKwh =
        entso_run:space_heat_demand_kw(AverageOutdoorTemp) * 24.0,
    ?assert(abs(ExpectedDailyKwh - ActualDailyKwh) < 1.0e-12).
