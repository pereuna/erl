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
    fetch_day(Day, normalize_utc(StartUtc0), normalize_utc(EndUtc0), place()).

fetch_days(DaySpecs) ->
    Place = place(),
    [fetch_day_spec(DaySpec, Place) || DaySpec <- DaySpecs].

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
    {Day, fetch_day(Day, normalize_utc(StartUtc), normalize_utc(EndUtc), Place)}.

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
        ok = file:write_file(TmpTemps, temps_txt(Measurements)),
        ok = file:rename(TmpObs, ObsOut),
        ok = file:rename(TmpFc, FcOut),
        ok = file:rename(TmpTemps, TempsOut),
        _ = file:delete(OldRawOut),
        Metadata = #{day => Day, place => Place, start => StartUtc, 'end' => EndUtc,
            obs_xml => ObsOut, fc_xml => FcOut, temps => TempsOut, measurements => Measurements},
        log("fmi: päivitetty päivä=~s paikka=~s väli=~s...~s tiedosto=~s", [Day, Place, StartUtc, EndUtc, TempsOut]),
        {ok, Metadata}
    catch
        Class:Reason:Stacktrace ->
            _ = file:delete(TmpObs),
            _ = file:delete(TmpFc),
            _ = file:delete(TmpTemps),
            log("fmi: ERROR päivä=~s paikka=~s väli=~s...~s ~p:~p", [Day, Place, StartUtc, EndUtc, Class, Reason]),
            logger:debug("fmi stacktrace: ~p", [Stacktrace]),
            {error, {Class, Reason}}
    end.

first_time(Key, Metadata) ->
    case maps:get(Key, Metadata, []) of
        [Time | _] -> Time;
        [] -> error({missing_entso_time, Key})
    end.

normalize_utc(Time) ->
    S = string:trim(Time),
    case {length(S), lists:suffix("Z", S)} of
        {17, true} ->
            lists:sublist(S, 16) ++ ":00Z";
        {20, true} ->
            S;
        _ ->
            error({invalid_utc_time, Time})
    end.

place() ->
    case os:getenv("FMI_PLACE") of
        false -> ?DEFAULT_PLACE;
        "" -> ?DEFAULT_PLACE;
        Place -> Place
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

temps_txt(Measurements) ->
    unicode:characters_to_binary([Value ++ "\n" || #{value := Value} <- Measurements]).

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
        time => xpath_string("*[local-name()='time']", Node),
        value => xpath_string("*[local-name()='value']", Node)}.

xpath_string(Path, Node) ->
    {_, _, Value} = xmerl_xpath:string("string(" ++ Path ++ ")", Node),
    unicode:characters_to_list(Value).

log(Format, Args) ->
    Line = io_lib:format("~s " ++ Format ++ "~n", [timestamp() | Args]),
    _ = filelib:ensure_dir(?LOG),
    _ = file:write_file(?LOG, Line, [append]),
    logger:info(Format, Args),
    ok.

timestamp() ->
    {{Y, M, D}, {H, Min, S}} = calendar:local_time(),
    lists:flatten(io_lib:format("~4..0B-~2..0B-~2..0B ~2..0B:~2..0B:~2..0B", [Y, M, D, H, Min, S])).
