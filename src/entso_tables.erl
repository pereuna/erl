%% entso_tables.erl
%% P55/COP55-taulukot Erlangin omana vektorina.
-module(entso_tables).

-export([p55/0, cop55/0, vector/2, value/3]).

-define(MIN_TEMP, -20).

%% Arvot ovat lämpötiloille -20..20 °C samassa järjestyksessä kuin vanhoissa
%% P55.txt/COP55.txt-tiedostoissa: tuple-elementti 1 vastaa -20 °C:ta.
%% Päivitä nämä numerot tässä moduulissa, jos laitekohtaiset taulukkoarvot
%% muuttuvat; run.txt-laskenta ei enää lue P55/COP55-arvoja tiedostosta.
p55() ->
    vector(?MIN_TEMP, {
        6.00, 6.10, 6.20, 6.30, 6.40,
        6.50, 6.60, 6.70, 6.80, 6.90,
        7.00, 7.10, 7.20, 7.30, 7.40,
        7.50, 7.60, 7.70, 7.80, 7.90,
        8.00, 8.10, 8.20, 8.30, 8.40,
        8.50, 8.60, 8.70, 8.80, 8.90,
        9.00, 9.10, 9.20, 9.30, 9.40,
        9.50, 9.60, 9.70, 9.80, 9.90,
        10.00
    }).

cop55() ->
    vector(?MIN_TEMP, {
        1.70, 1.74, 1.78, 1.82, 1.86,
        1.90, 1.94, 1.98, 2.02, 2.06,
        2.10, 2.14, 2.18, 2.22, 2.26,
        2.30, 2.34, 2.38, 2.42, 2.46,
        2.50, 2.54, 2.58, 2.62, 2.66,
        2.70, 2.74, 2.78, 2.82, 2.86,
        2.90, 2.94, 2.98, 3.02, 3.06,
        3.10, 3.14, 3.18, 3.22, 3.26,
        3.30
    }).

value(Temp, Vector, Name) ->
    case vector_value(Temp, Vector) of
        {ok, Value} -> Value;
        error -> error({missing_temp_vector_value, Name, Temp})
    end.

vector(MinTemp, Values) when is_integer(MinTemp), is_tuple(Values) ->
    {temp_vector, MinTemp, Values}.

vector_value(Temp, {temp_vector, MinTemp, Values}) when is_integer(Temp) ->
    Index = Temp - MinTemp + 1,
    case Index >= 1 andalso Index =< tuple_size(Values) of
        true -> {ok, element(Index, Values)};
        false -> error
    end.
