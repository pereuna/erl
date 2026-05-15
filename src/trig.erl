%% trig.erl
%% Tarkistaa nykyisen UTC-vartin ohjaustaulukosta ja asettaa GPIO-ulostulot.
-module(trig).

-export([do_work/0, do_work/1, action_for_time/1, action_for_time/2, current_quarter_utc/0]).

-define(DEFAULT_GPIO_DEVICE, "gpio0").
-define(DEFAULT_PUMP_PIN, 26).
-define(DEFAULT_CONTROL_PIN, 20).
-define(GPIO_COMMAND, "/usr/sbin/gpioctl").

%% API: varttiajastimesta kutsuttava työ.
do_work() ->
    do_work(current_quarter_utc()).

do_work(TimeUtc) ->
    case action_for_time(TimeUtc) of
        {ok, Action} ->
            case apply_action(Action) of
                ok ->
                    logger:info("trig: time=~s action=~p", [TimeUtc, Action]),
                    {ok, Action};
                {error, Reason} ->
                    logger:error("trig: gpio failed time=~s action=~p reason=~p", [TimeUtc, Action, Reason]),
                    {error, Reason}
            end;
        {error, Reason} ->
            logger:error("trig: plan lookup failed time=~s reason=~p", [TimeUtc, Reason]),
            {error, Reason}
    end.

%% Palauttaa valittavan toiminnon ilman GPIO-sivuvaikutuksia.
%% Oikeassa ajossa suunnitelma koostetaan aina levyltä löytyvistä prices.txt- ja
%% temps.txt-tiedostoista, ja samalla run.txt päivittyy lokiksi.
action_for_time(TimeUtc) ->
    normalize_lookup_result(entso_run:action_for_time(TimeUtc)).

%% Testi-/käsikäyttöön: anna suoraan #{TimeUtc => charge | discharge} -map.
action_for_time(Plan, TimeUtc) when is_map(Plan) ->
    normalize_lookup_result(maps:get(TimeUtc, Plan, normal)).

current_quarter_utc() ->
    {{Y, M, D}, {H, Min, _S}} = calendar:universal_time(),
    QuarterMin = (Min div 15) * 15,
    lists:flatten(
        io_lib:format(
            "~4..0B-~2..0B-~2..0BT~2..0B:~2..0B:00Z",
            [Y, M, D, H, QuarterMin]
        )
    ).

normalize_lookup_result({ok, Action}) ->
    normalize_lookup_result(Action);
normalize_lookup_result({error, Reason}) ->
    {error, Reason};
normalize_lookup_result(Action) when Action =:= normal; Action =:= charge; Action =:= discharge ->
    {ok, Action};
normalize_lookup_result(Other) ->
    {error, {invalid_action, Other}}.

apply_action(normal) ->
    set_outputs(1, 1);
apply_action(charge) ->
    set_outputs(1, 0);
apply_action(discharge) ->
    set_outputs(0, 1).

set_outputs(PumpValue, ControlValue) ->
    case run_gpio(?GPIO_COMMAND, ?DEFAULT_GPIO_DEVICE, ?DEFAULT_PUMP_PIN, PumpValue) of
        ok -> run_gpio(?GPIO_COMMAND, ?DEFAULT_GPIO_DEVICE, ?DEFAULT_CONTROL_PIN, ControlValue);
        Error -> Error
    end.

run_gpio(Command, Device, Pin, Value) ->
    Args = [Device, integer_to_list(Pin), integer_to_list(Value)],
    Port = open_port({spawn_executable, Command}, [exit_status, {args, Args}, use_stdio, stderr_to_stdout]),
    collect_gpio_result(Port, []).

collect_gpio_result(Port, Acc) ->
    receive
        {Port, {data, Data}} ->
            collect_gpio_result(Port, [Data | Acc]);
        {Port, {exit_status, 0}} ->
            ok;
        {Port, {exit_status, Status}} ->
            Output = unicode:characters_to_list(lists:reverse(Acc)),
            {error, {gpio_exit_status, Status, Output}}
    after 30000 ->
        port_close(Port),
        {error, gpio_timeout}
    end.
