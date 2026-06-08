%% karl [YYYY-MM-DD]
-module(kurl).

-include_lib("kernel/include/file.hrl").
-include_lib("xmerl/include/xmerl.hrl").
-export([fetch_day/1]).

-define(HOST, "web-api.tp.entsoe.eu").
-define(DOM, "10YFI-1--------U").
-define(PX, "/var/www/htdocs/jedi.ydns.eu/var").
-define(API_KEY_FILE, "/etc/quarter/entsoe_api_key").

apikey() ->
    apikey([
        application_env,
        {env, "ENTSOE_API_KEY"},
        {file, api_key_file()}
    ]).

apikey([]) ->
    {error, {missing_config, entsoe_api_key}};
apikey([Source | Rest]) ->
    case api_key_from(Source) of
        {ok, ApiKey} -> {ok, ApiKey};
        skip -> apikey(Rest)
    end.

api_key_from(application_env) ->
    case application:get_env(quarter, entsoe_api_key) of
        {ok, ApiKey} -> normalize_api_key(ApiKey);
        undefined -> skip
    end;
api_key_from({env, Name}) ->
    case os:getenv(Name) of
        false -> skip;
        ApiKey -> normalize_api_key(ApiKey)
    end;
api_key_from({file, Path}) ->
    case file:read_file(Path) of
        {ok, Body} -> normalize_api_key(Body);
        {error, _} -> skip
    end.

api_key_file() ->
    case application:get_env(quarter, entsoe_api_key_file) of
        {ok, Path} -> Path;
        undefined -> ?API_KEY_FILE
    end.

normalize_api_key(ApiKey0) when is_binary(ApiKey0) ->
    normalize_api_key(unicode:characters_to_list(ApiKey0));
normalize_api_key(ApiKey0) when is_list(ApiKey0) ->
    ApiKey = string:trim(ApiKey0),
    case ApiKey of
        "" -> skip;
        "${" ++ _ -> skip;
        _ -> {ok, ApiKey}
    end;
normalize_api_key(_ApiKey) ->
    skip.

%% Fetch one UTC day into /var/www/.../var/YYYY/MM/DD/entso.xml.
%% entso_st.txt and entso_end.txt are intentionally not written anymore;
%% their values are returned as Erlang data in the metadata map.
fetch_day(Day) ->
    DayDir = filename:join([?PX | string:split(Day, "-", all)]),
    Out = filename:join(DayDir, "entso.xml"),
    Tmp = filename:join(DayDir, ".entso.xml.tmp"),
    ok = filelib:ensure_dir(filename:join(DayDir, "dummy")),
    case existing_xml_metadata(Out) of
        {ok, Metadata} ->
            logger:info("get_entso_xml: ~s on jo olemassa ja sisältää start-kentän, ei haeta", [Out]),
            {ok, Metadata};
        missing ->
            fetch_day(Day, Out, Tmp);
        invalid ->
            logger:info("get_entso_xml: ~s on olemassa mutta start-kenttä puuttuu, haetaan uudestaan", [Out]),
            fetch_day(Day, Out, Tmp)
    end.

fetch_day(Day, Out, Tmp) ->
    case apikey() of
        {ok, Api} ->
            fetch_day_with_api_key(Day, Out, Tmp, Api);
        {error, Reason} ->
            logger:info("get_entso_xml: ERROR day=~s ~p", [Day, Reason]),
            {error, Reason}
    end.

fetch_day_with_api_key(Day, Out, Tmp, Api) ->
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
                    xml_parse:write_prices(Out),
                    Metadata = Metadata0#{file => Out},
                    logger:info("get_entso_xml: haettu ~s", [Out]),
                    {ok, Metadata};
                _ ->
                    _ = file:delete(Tmp),
                    logger:info(
                        "get_entso_xml: ERROR day=~s ladattu XML ei sisällä start-kenttää",
                        [Day]
                    ),
                    {error, missing_start}
            end;
        {ok, {{_, Code, _}, _Headers, _Body}} ->
            _ = file:delete(Tmp),
            logger:info("get_entso_xml: ERROR day=~s HTTP=~p", [Day, Code]),
            {error, {http_status, Code}};
        {error, Reason} ->
            _ = file:delete(Tmp),
            logger:info("get_entso_xml: ERROR day=~s ~p", [Day, Reason]),
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

entsoe_url(Date, Api) ->
    Interval = Date ++ "T09%3A00Z%2F" ++ Date ++ "T15%3A00Z",
    Query = "documentType=A44&in_Domain=" ++ ?DOM ++
        "&out_Domain=" ++ ?DOM ++
        "&timeInterval=" ++ Interval ++
        "&securityToken=" ++ Api,
    "https://" ++ ?HOST ++ "/api?" ++ Query.
