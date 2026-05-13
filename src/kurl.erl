%% karl [YYYY-MM-DD]
-module(kurl).

-include_lib("kernel/include/file.hrl").
-include_lib("xmerl/include/xmerl.hrl").
-export([fetch_day/1, getpage/1]).

-define(HOST, "web-api.tp.entsoe.eu").
-define(DOM, "10YFI-1--------U").
-define(PX, "/var/www/htdocs/jedi.ydns.eu/var").
-define(VOL, "/var/www/htdocs/jedi.ydns.eu/volatile").
-define(LOG, "/var/www/htdocs/jedi.ydns.eu/volatile/entso.log").

apikey() ->
    case os:getenv("ENTSOE_API_KEY") of
        false -> error({missing_env, "ENTSOE_API_KEY"});
        "" -> error({empty_env, "ENTSOE_API_KEY"});
        ApiKey -> {api_key, ApiKey}
    end.

%% Fetch one UTC day into /var/www/.../var/YYYY/MM/DD/entso.xml.
%% entso_st.txt and entso_end.txt are intentionally not written anymore;
%% their values are returned as Erlang data in the metadata map.
fetch_day(Day) ->
    DayDir = filename:join([?PX | string:split(Day, "-", all)]),
    Out = filename:join(DayDir, "entso.xml"),
    Tmp = filename:join(?VOL, "." ++ Day ++ ".xml.tmp"),
    ok = filelib:ensure_dir(filename:join(DayDir, "dummy")),
    case existing_xml_metadata(Out) of
        {ok, Metadata} ->
            ensure_prices(Out),
            eutils:log(?LOG, "get_entso_xml: ~s on jo olemassa ja sisältää start-kentän, ei haeta", [Out]),
            {ok, Metadata};
        missing ->
            fetch_day(Day, Out, Tmp);
        invalid ->
            eutils:log(?LOG, "get_entso_xml: ~s on olemassa mutta start-kenttä puuttuu, haetaan uudestaan", [Out]),
            fetch_day(Day, Out, Tmp)
    end.

fetch_day(Day, Out, Tmp) ->
    {api_key, Api} = apikey(),
    application:ensure_all_started(ssl),
    application:ensure_all_started(inets),
    Url = entsoe_url(Day, Api),
    Request = {Url, []},
    HttpOptions = [{connect_timeout, 30000}, {timeout, 240000}],
    Options = [{body_format, binary}],
    Result = httpc:request(get, Request, HttpOptions, Options),
    case Result of
        {ok, {{_, 200, _}, _Headers, Body}} when byte_size(Body) > 0 ->
            ok = file:write_file(Tmp, Body),
            case existing_xml_metadata(Tmp) of
                {ok, Metadata0} ->
                    ok = file:rename(Tmp, Out),
                    ensure_prices(Out),
                    Metadata = Metadata0#{file => Out},
                    eutils:log(?LOG, "get_entso_xml: haettu ~s", [Out]),
                    {ok, Metadata};
                _ ->
                    _ = file:delete(Tmp),
                    eutils:log(?LOG, "get_entso_xml: ERROR day=~s ladattu XML ei sisällä start-kenttää", [Day]),
                    {error, missing_start}
            end;
        {ok, {{_, Code, _}, _Headers, _Body}} ->
            _ = file:delete(Tmp),
            eutils:log(?LOG, "get_entso_xml: ERROR day=~s HTTP=~p", [Day, Code]),
            {error, {http_status, Code}};
        {error, Reason} ->
            _ = file:delete(Tmp),
            eutils:log(?LOG, "get_entso_xml: ERROR day=~s ~p", [Day, Reason]),
            {error, Reason}
    end.

existing_xml_metadata(Out) ->
    case file:read_file_info(Out) of
        {ok, #file_info{size = Size}} when Size > 0 ->
            xml_metadata(Out);
        {ok, _} ->
            invalid;
        {error, enoent} ->
            missing;
        {error, _} ->
            missing
    end.

xml_metadata(File) ->
    try
        {Doc, _} = xmerl_scan:file(File),
        Starts = xmerl_xpath:string("//*[local-name()='timeInterval']/*[local-name()='start']/text()", Doc),
        Ends = xmerl_xpath:string("//*[local-name()='timeInterval']/*[local-name()='end']/text()", Doc),
        StartValues = text_values(Starts),
        EndValues = text_values(Ends),
        case StartValues of
            [] ->
                invalid;
            _ ->
                {ok, #{file => File, start => StartValues, 'end' => EndValues}}
        end
    catch
        _:_ -> invalid
    end.

text_values(TextNodes) ->
    [unicode:characters_to_list(Value) || #xmlText{value = Value} <- TextNodes].

ensure_prices(EntsoXml) ->
    case xml_parse:write_prices(EntsoXml) of
        {ok, #{prices := PricesFile, rows := Rows}} ->
            eutils:log(?LOG, "get_entso_xml: kirjoitettu ~s rivejä=~p", [PricesFile, Rows]),
            ok
    end.

entsoe_url(Date, Api) ->
    Interval = Date ++ "T09%3A00Z%2F" ++ Date ++ "T15%3A00Z",
    Query = "documentType=A44&in_Domain=" ++ ?DOM ++
        "&out_Domain=" ++ ?DOM ++
        "&timeInterval=" ++ Interval ++
        "&securityToken=" ++ Api,
    "https://" ++ ?HOST ++ "/api?" ++ Query.
