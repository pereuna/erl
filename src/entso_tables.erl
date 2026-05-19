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

%% Menoveden tavoitelämpötila "normal"-tilalle.
%% Clampataan taulukon alueelle 25..60 C.
target_supply_temp(OutdoorTemp) ->
    %% Lineaarinen säätökäyrä:
    %% ulkoT = 22 C -> menovesi 22 C
    %% ulkoT = -15 C -> menovesi 55 C
    %% Laskennassa alle 25 C menovedet clampataan 25 C taulukkoarvoihin.
    Target = 22.0 + ((22.0 - OutdoorTemp) * (33.0 / 37.0)),
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

%% Käyttäjän toimittama taulukko (cap) lämpöteholle kW.
p_table() ->
    #{
        -20 => #{25 => 9.3, 35 => 9.3, 40 => 9.3, 45 => 9.3, 50 => 9.1, 55 => 8.9, 60 => 8.7},
        -15 => #{25 => 10.0, 35 => 10.0, 40 => 10.0, 45 => 10.0, 50 => 10.0, 55 => 10.0, 60 => 9.5},
        -10 => #{25 => 10.8, 35 => 10.8, 40 => 10.8, 45 => 10.8, 50 => 10.8, 55 => 10.8, 60 => 10.6},
        -7  => #{25 => 11.2, 35 => 11.2, 40 => 11.2, 45 => 11.2, 50 => 11.2, 55 => 11.2, 60 => 11.2},
        2   => #{25 => 11.2, 35 => 11.2, 40 => 11.2, 45 => 11.2, 50 => 11.2, 55 => 11.2, 60 => 11.2},
        7   => #{25 => 11.2, 35 => 11.2, 40 => 11.2, 45 => 11.2, 50 => 11.2, 55 => 11.2, 60 => 11.2},
        12  => #{25 => 11.2, 35 => 11.2, 40 => 11.2, 45 => 11.2, 50 => 11.2, 55 => 11.2, 60 => 11.2},
        15  => #{25 => 11.2, 35 => 11.2, 40 => 11.2, 45 => 11.2, 50 => 11.2, 55 => 11.2, 60 => 11.2},
        20  => #{25 => 11.2, 35 => 11.2, 40 => 11.2, 45 => 11.2, 50 => 11.2, 55 => 11.2, 60 => 11.2}
    }.

%% Käyttäjän toimittama COP-taulukko.
cop_table() ->
    #{
        -20 => #{25 => 1.8, 35 => 1.6, 40 => 1.51, 45 => 1.41, 50 => 1.37, 55 => 1.34, 60 => 1.31},
        -15 => #{25 => 2.34, 35 => 1.96, 40 => 1.82, 45 => 1.67, 50 => 1.51, 55 => 1.34, 60 => 1.30},
        -10 => #{25 => 2.72, 35 => 2.32, 40 => 2.12, 45 => 1.93, 50 => 1.72, 55 => 1.52, 60 => 1.46},
        -7  => #{25 => 2.99, 35 => 2.53, 40 => 2.31, 45 => 2.09, 50 => 1.86, 55 => 1.62, 60 => 1.55},
        2   => #{25 => 3.50, 35 => 3.11, 40 => 2.86, 45 => 2.61, 50 => 2.35, 55 => 2.08, 60 => 1.86},
        7   => #{25 => 4.75, 35 => 4.43, 40 => 3.91, 45 => 3.39, 50 => 2.94, 55 => 2.48, 60 => 2.14},
        12  => #{25 => 5.46, 35 => 4.61, 40 => 4.08, 45 => 3.54, 50 => 3.06, 55 => 2.59, 60 => 2.22},
        15  => #{25 => 5.65, 35 => 4.73, 40 => 4.17, 45 => 3.62, 50 => 3.14, 55 => 2.65, 60 => 2.26},
        20  => #{25 => 5.80, 35 => 4.91, 40 => 4.34, 45 => 3.77, 50 => 3.27, 55 => 2.76, 60 => 2.34}
    }.

clamp(V, Min, _Max) when V < Min -> Min;
clamp(V, _Min, Max) when V > Max -> Max;
clamp(V, _Min, _Max) -> V.
