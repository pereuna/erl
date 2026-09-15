%% entso_tables.erl
%% P/COP taulukot 2D-muodossa (Tout x Tsupply)
-module(entso_tables).
-export([p55/0, cop55/0, p/2, cop/2, target_supply_temp/1]).

-define(TOUT_POINTS, [-20, -15, -10, -7, 2, 7, 12, 15, 20]).
-define(TSUPPLY_POINTS, [25, 35, 40, 45, 50, 55, 60]).

%% 55 C -sarakkeesta johdettu yhteensopivuusrajapinta, interpoloituna 1 C välein.
p55() ->
    maps:from_list([{T, p(T, 55)} || T <- lists:seq(-20, 20)]).

cop55() ->
    maps:from_list([{T, cop(T, 55)} || T <- lists:seq(-20, 20)]).

%% Menoveden tavoitelämpötila "normal"-tilalle. Kaava on sama kuin vanhassa
%% /rc/trilogy-ohjauksessa. Clampataan taulukon alueelle 25..60 C.
target_supply_temp(OutdoorTemp) ->
    Target = -0.0067 * OutdoorTemp - 0.9 * OutdoorTemp + 42.7,
    clamp(Target, 25.0, 60.0).

%% COP(Tout, Tsupply) 2D-taulukosta bilineaarisesti interpoloituna.
cop(OutdoorTemp, SupplyTemp) ->
    interp2d(cop_table(), OutdoorTemp, SupplyTemp).

%% P(Tout, Tsupply) 2D-taulukosta bilineaarisesti interpoloituna.
p(OutdoorTemp, SupplyTemp) ->
    interp2d(p_table(), OutdoorTemp, SupplyTemp).

interp2d(Table, Tout0, Tsupply0) ->
    Tout = clamp(Tout0, -20.0, 20.0),
    Tsupply = clamp(Tsupply0, 25.0, 60.0),
    {T1, T2, Tw} = bracket(Tout, ?TOUT_POINTS),
    {S1, S2, Sw} = bracket(Tsupply, ?TSUPPLY_POINTS),
    V11 = cell(Table, T1, S1),
    V12 = cell(Table, T1, S2),
    V21 = cell(Table, T2, S1),
    V22 = cell(Table, T2, S2),
    Vt1 = lerp(V11, V12, Sw),
    Vt2 = lerp(V21, V22, Sw),
    lerp(Vt1, Vt2, Tw).

bracket(_X, [P]) ->
    {P, P, 0.0};
bracket(X, [A, _B | _]) when X =< A ->
    {A, A, 0.0};
bracket(X, [A, B | _]) when X >= A, X =< B ->
    W = case B - A of
            0 -> 0.0;
            D -> (X - A) / D
        end,
    {A, B, W};
bracket(X, [_A | Rest]) ->
    bracket(X, Rest).

cell(Table, Tout, Tsupply) ->
    Row = maps:get(Tout, Table),
    maps:get(Tsupply, Row).

lerp(A, B, W) -> A + (B - A) * W.

%% Mitsubishi PUHZ-SHW112V/YHA(-BS) -taulukon Max/Capacity-arvot (kW).
%% Valmistajan taulukossa olevat tyhjät reunapisteet on täytetty vanhojen
%% /www/const/P.txt-arvojen avulla, jotta interpolointi toimii koko alueella.
p_table() ->
    #{
        -20 => #{25 => 10.5, 35 => 10.5, 40 => 10.5, 45 => 10.5, 50 => 10.4, 55 => 10.3, 60 => 10.0},
        -15 => #{25 => 13.6, 35 => 13.6, 40 => 13.4, 45 => 13.2, 50 => 13.1, 55 => 12.9, 60 => 10.2},
        -10 => #{25 => 14.8, 35 => 14.4, 40 => 14.2, 45 => 14.0, 50 => 13.9, 55 => 13.9, 60 => 10.5},
        -7  => #{25 => 15.3, 35 => 14.9, 40 => 14.7, 45 => 14.5, 50 => 14.5, 55 => 14.4, 60 => 11.0},
        2   => #{25 => 14.1, 35 => 13.5, 40 => 13.1, 45 => 12.8, 50 => 12.5, 55 => 12.2, 60 => 11.7},
        7   => #{25 => 15.7, 35 => 14.8, 40 => 14.4, 45 => 14.0, 50 => 13.6, 55 => 13.2, 60 => 12.8},
        12  => #{25 => 18.1, 35 => 17.1, 40 => 16.5, 45 => 15.8, 50 => 15.4, 55 => 14.9, 60 => 14.6},
        15  => #{25 => 19.4, 35 => 18.6, 40 => 17.8, 45 => 16.9, 50 => 16.4, 55 => 16.0, 60 => 15.6},
        20  => #{25 => 20.7, 35 => 19.7, 40 => 19.2, 45 => 18.7, 50 => 18.2, 55 => 17.7, 60 => 17.4}
    }.

%% Saman valmistajataulukon Max/COP-arvot. Tyhjien reunapisteiden arvot ovat
%% vanhasta /www/const/cop.txt-taulukosta.
cop_table() ->
    #{
        -20 => #{25 => 2.30, 35 => 2.14, 40 => 1.93, 45 => 1.73, 50 => 1.50, 55 => 1.30, 60 => 1.10},
        -15 => #{25 => 2.50, 35 => 2.17, 40 => 1.97, 45 => 1.77, 50 => 1.57, 55 => 1.36, 60 => 1.30},
        -10 => #{25 => 2.69, 35 => 2.40, 40 => 2.15, 45 => 1.91, 50 => 1.72, 55 => 1.52, 60 => 1.40},
        -7  => #{25 => 2.83, 35 => 2.54, 40 => 2.27, 45 => 1.99, 50 => 1.82, 55 => 1.61, 60 => 1.50},
        2   => #{25 => 3.37, 35 => 3.10, 40 => 2.81, 45 => 2.51, 50 => 2.24, 55 => 1.95, 60 => 1.61},
        7   => #{25 => 4.54, 35 => 4.04, 40 => 3.65, 45 => 3.26, 50 => 2.93, 55 => 2.58, 60 => 2.31},
        12  => #{25 => 5.06, 35 => 4.52, 40 => 4.03, 45 => 3.54, 50 => 3.20, 55 => 2.85, 60 => 2.56},
        15  => #{25 => 5.38, 35 => 4.84, 40 => 4.27, 45 => 3.71, 50 => 3.38, 55 => 3.01, 60 => 2.71},
        20  => #{25 => 5.54, 35 => 5.06, 40 => 4.52, 45 => 3.99, 50 => 3.65, 55 => 3.28, 60 => 2.96}
    }.

clamp(V, Min, _Max) when V < Min -> Min;
clamp(V, _Min, Max) when V > Max -> Max;
clamp(V, _Min, _Max) -> V.
