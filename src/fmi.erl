%% fmi.erl
%% Fetch FMI observations, forecasts, and temps.txt into the same day directories as entso.xml.
-module(fmi).

-include_lib("kernel/include/file.hrl").
-include_lib("xmerl/include/xmerl.hrl").

-export([fetch_day/1, fetch_day/3, fetch_days/1, fetch_today_and_tomorrow/0]).

-define(BASE_URL, "https://opendata.fmi.fi/wfs").
-define(DEFAULT_PLACE, "Pihlava").
-define(PX, "/var/www/htdocs/jedi.ydns.eu/var").
-define(VOL, "/var/www/htdocs/jedi.ydns.eu/volatile").
-define(LOG, "/var/www/htdocs/jedi.ydns.eu/volatile/fmi.log").

%% Fetch current day and next day using the same start/end values that ENTSO XML contains.
fetch_today_and_tomorrow() ->
    fetch_days_from_entso([eutils:today_utc_string(), eutils:tomorrow_utc_string()]).

fetch_day(Day) ->
    case kurl:fetch_day(Day) of
        {ok, Metadata} ->
            fetch_day(Day, first_time(start, Metadata), first_time('end', Metadata));
        {error, Reason} ->
            {error, Reason}
    end.

fetch_day(Day, StartUtc0, EndUtc0) ->
    fetch_day(Day, eutils:normalize_utc(StartUtc0), eutils:normalize_utc(EndUtc0), ?DEFAULT_PLACE).

fetch_days(DaySpecs) ->
    [fetch_day_spec(DaySpec, ?DEFAULT_PLACE) || DaySpec <- DaySpecs].

fetch_days_from_entso(Days) ->
    fetch_days([entso_day_spec(Day) || Day <- Days]).

entso_day_spec(Day) ->
    case kurl:fetch_day(Day) of
        {ok, Metadata} ->
            {Day, first_time(start, Metadata), first_time('end', Metadata)};
        {error, Reason} ->
            {Day, {error, Reason}}
    end.

fetch_day_spec({Day, {error, Reason}}, _Place) ->
    {Day, {error, Reason}};
fetch_day_spec({Day, StartUtc, EndUtc}, Place) ->
    {Day, fetch_day(Day, eutils:normalize_utc(StartUtc), eutils:normalize_utc(EndUtc), Place)}.

fetch_day(Day, StartUtc, EndUtc, Place) ->
    DayDir = day_dir(Day),
    ObsOut = filename:join(DayDir, "fmi_obs.xml"),
    FcOut = filename:join(DayDir, "fmi_fc.xml"),
    TempsOut = filename:join(DayDir, "temps.txt"),
    OldRawOut = filename:join(DayDir, "fmi_raw.tsv"),
    TmpObs = filename:join(?VOL, ".fmi_obs_" ++ Day ++ ".xml.tmp"),
    TmpFc = filename:join(?VOL, ".fmi_fc_" ++ Day ++ ".xml.tmp"),
    TmpTemps = filename:join(?VOL, ".temps_" ++ Day ++ ".txt.tmp"),
    ok = filelib:ensure_dir(filename:join(DayDir, "dummy")),
    ok = filelib:ensure_dir(filename:join(?VOL, "dummy")),
    ObsUrl = fmi_url("fmi::observations::weather::timevaluepair", Place, "t2m", StartUtc, EndUtc),
    FcUrl = fmi_url("fmi::forecast::harmonie::surface::point::timevaluepair", Place, "Temperature", StartUtc, EndUtc),
    try
        ok = require_ok(fetch(ObsUrl, TmpObs), {fetch_obs, Day}),
        ok = require_ok(fetch(FcUrl, TmpFc), {fetch_forecast, Day}),
        Measurements = measurements(TmpObs, TmpFc),
        ok = file:write_file(TmpTemps, temps_txt(Measurements, StartUtc, EndUtc)),
        ok = file:rename(TmpObs, ObsOut),
        ok = file:rename(TmpFc, FcOut),
        ok = file:rename(TmpTemps, TempsOut),
        _ = file:delete(OldRawOut),
        Metadata = #{day => Day, place => Place, start => StartUtc, 'end' => EndUtc,
            obs_xml => ObsOut, fc_xml => FcOut, temps => TempsOut, measurements => Measurements},
        eutils:log(?LOG, "fmi: päivitetty päivä=~s paikka=~s väli=~s...~s tiedosto=~s", [Day, Place, StartUtc, EndUtc, TempsOut]),
        {ok, Metadata}
    catch
        Class:Reason:Stacktrace ->
            _ = file:delete(TmpObs),
            _ = file:delete(TmpFc),
            _ = file:delete(TmpTemps),
            eutils:log(?LOG, "fmi: ERROR päivä=~s paikka=~s väli=~s...~s ~p:~p", [Day, Place, StartUtc, EndUtc, Class, Reason]),
            logger:debug("fmi stacktrace: ~p", [Stacktrace]),
            {error, {Class, Reason}}
    end.

first_time(Key, Metadata) ->
    case maps:get(Key, Metadata, []) of
        [Time | _] -> Time;
        [] -> error({missing_entso_time, Key})
    end.

day_dir(Day) ->
    filename:join([?PX | string:split(Day, "-", all)]).

fmi_url(StoredQueryId, Place, Parameters, StartUtc, EndUtc) ->
    Query = [
        {"service", "WFS"},
        {"version", "2.0.0"},
        {"request", "getFeature"},
        {"storedquery_id", StoredQueryId},
        {"place", Place},
        {"parameters", Parameters},
        {"starttime", StartUtc},
        {"endtime", EndUtc}
    ],
    ?BASE_URL ++ "?" ++ uri_string:compose_query(Query).

fetch(Url, Out) ->
    application:ensure_all_started(ssl),
    application:ensure_all_started(inets),
    Request = {Url, []},
    HttpOptions = [{connect_timeout, 10000}, {timeout, 30000}],
    Options = [{body_format, binary}],
    case httpc:request(get, Request, HttpOptions, Options) of
        {ok, {{_, 200, _}, _Headers, Body}} when byte_size(Body) > 0 ->
            file:write_file(Out, Body);
        {ok, {{_, 200, _}, _Headers, _Body}} ->
            {error, empty_body};
        {ok, {{_, Code, _}, _Headers, _Body}} ->
            {error, {http_status, Code}};
        {error, Reason} ->
            {error, Reason}
    end.

require_ok(ok, _Context) ->
    ok;
require_ok({error, Reason}, Context) ->
    error({Context, Reason}).

measurements(ObsXml, FcXml) ->
    Obs = parse_timevaluepair(havainto, ObsXml),
    Fc = parse_timevaluepair(ennuste, FcXml),
    Obs ++ Fc.

temps_txt(Measurements, StartUtc0, EndUtc0) ->
    StartUtc = eutils:normalize_utc(StartUtc0),
    EndUtc = eutils:normalize_utc(EndUtc0),
    StartEpoch = eutils:utc_to_epoch(StartUtc),
    EndEpoch = eutils:utc_to_epoch(EndUtc),
    case EndEpoch > StartEpoch of
        true -> ok;
        false -> error({invalid_time_interval, StartUtc, EndUtc})
    end,
    Obs = series(havainto, Measurements),
    Fc = series(ennuste, Measurements),
    Lines = [temperature_line(Epoch, Obs, Fc) || Epoch <- lists:seq(StartEpoch, EndEpoch - 900, 900)],
    unicode:characters_to_binary(Lines).

series(Type, Measurements) ->
    Points = [
        {Epoch, Temp}
        || #{type := MType, time := Time, value := Value} <- Measurements,
            MType =:= Type,
            {ok, Epoch} <- [eutils:utc_to_epoch_safe(Time)],
            {ok, Temp} <- [temperature_to_float(Value)]
    ],
    lists:sort(maps:to_list(maps:from_list(Points))).

temperature_line(Epoch, Obs, Fc) ->
    Temp = case value_at(Obs, Epoch, no_extrapolate) of
        {ok, ObsTemp} -> ObsTemp;
        unavailable ->
            case value_at(Fc, Epoch, extrapolate) of
                {ok, FcTemp} -> FcTemp;
                unavailable -> error({missing_temperature, eutils:epoch_to_utc(Epoch)})
            end
    end,
    lists:flatten(io_lib:format("~s ~B~n", [eutils:epoch_to_utc(Epoch), round(Temp)])).

value_at([], _Epoch, _Mode) ->
    unavailable;
value_at([{Epoch, Temp} | _], Epoch, _Mode) ->
    {ok, Temp};
value_at([{FirstEpoch, FirstTemp} | _], Epoch, extrapolate) when Epoch < FirstEpoch ->
    {ok, FirstTemp};
value_at(Series, Epoch, Mode) ->
    value_at(Series, Epoch, Mode, unavailable).

value_at([{Epoch, Temp} | _], Epoch, _Mode, _Prev) ->
    {ok, Temp};
value_at([{NextEpoch, NextTemp} | _], Epoch, _Mode, {PrevEpoch, PrevTemp}) when PrevEpoch < Epoch, Epoch < NextEpoch ->
    Fraction = (Epoch - PrevEpoch) / (NextEpoch - PrevEpoch),
    {ok, PrevTemp + Fraction * (NextTemp - PrevTemp)};
value_at([{PointEpoch, PointTemp}], Epoch, extrapolate, _Prev) when Epoch > PointEpoch ->
    {ok, PointTemp};
value_at([{PointEpoch, PointTemp} | Rest], Epoch, Mode, _Prev) when PointEpoch < Epoch ->
    value_at(Rest, Epoch, Mode, {PointEpoch, PointTemp});
value_at(_Series, _Epoch, _Mode, _Prev) ->
    unavailable.

temperature_to_float(Value0) ->
    Value = string:trim(Value0),
    case string:lowercase(Value) of
        "nan" -> error;
        "" -> error;
        _ ->
            case string:to_float(Value) of
                {Float, []} -> {ok, Float};
                {error, no_float} ->
                    case string:to_integer(Value) of
                        {Int, []} -> {ok, Int * 1.0};
                        _ -> error
                    end;
                _ -> error
            end
    end.

parse_timevaluepair(Label, File) ->
    case file:read_file_info(File) of
        {ok, #file_info{size = Size}} when Size > 0 ->
            {Doc, _} = xmerl_scan:file(File),
            Nodes = xmerl_xpath:string("//*[local-name()='MeasurementTVP']", Doc),
            [measurement(Label, Node) || Node <- Nodes];
        _ ->
            error({missing_or_empty_xml, File})
    end.

measurement(Label, Node) ->
    #{type => Label,
        time => eutils:xpath_string("*[local-name()='time']", Node),
        value => eutils:xpath_string("*[local-name()='value']", Node)}.
