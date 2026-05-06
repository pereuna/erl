%% karl [YYYY-MM-DD]
-module(kurl).
-export([getpage/1]).

-define(HOST, "web-api.tp.entsoe.eu").
-define(DOM, "10YFI-1--------U").

apikey() ->
    case os:getenv("ENTSOE_API_KEY") of
        false ->
            error({missing_env, "ENTSOE_API_KEY"});
        "" ->
            error({empty_env, "ENTSOE_API_KEY"});
        ApiKey ->
            {api_key, ApiKey}
    end.

getpage(Date) ->
    {api_key, Api} = apikey(),
    application:ensure_all_started(ssl),
    application:ensure_all_started(inets),
    Interval = Date ++ "T09%3A00Z%2F" ++ Date ++ "T15%3A00Z",
    Query = "documentType=A44&in_Domain=" ++ ?DOM ++
        "&out_Domain=" ++ ?DOM ++
        "&timeInterval=" ++ Interval ++
        "&securityToken=" ++ Api,
    Url = "https://" ++ ?HOST ++ "/api?" ++ Query,

    {ok, {{_, Code, _}, _, CodeBase}} = httpc:request(Url),
    {ok, Code, CodeBase}.
