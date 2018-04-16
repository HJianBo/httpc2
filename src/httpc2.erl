-module(httpc2).

-export([new/0, new/1]).

%% API
-export([get/2, get/3, get/4, post/3, post/4, post/5]).

%% Utils
-export([basic_auth/2]).

-import(proplists, [get_value/2]).

-define(HTTPC_MOD, {?MODULE, [_H]}).
-define(HTTPC_HDR(H), {?MODULE, [H]}).

-define(CONTENT_TYPE, "application/json").
-define(HEADERS, []).

%%--------------------------------------------------------------------
%% APIs
%%--------------------------------------------------------------------

new() -> new([]).

new(Headers) ->
    {ok, _} = application:ensure_all_started(inets),
    {?MODULE, [merge_opts(?HEADERS, Headers)]}.

get(Url, MOD = ?HTTPC_MOD) ->
    get(Url, [], MOD).

get(Url, QueryStrings, MOD = ?HTTPC_MOD) ->
    get(Url, QueryStrings, [], MOD).

get(Url, QueryStrings, ExHeaders, ?HTTPC_HDR(Headers)) when is_list(QueryStrings) ->
    Headers = merge_opts(Headers, ExHeaders),
    request(get, genrequest(param_uri(Url, QueryStrings), Headers), [], []).

post(Url, Params, MOD = ?HTTPC_MOD) ->
    post(Url, [], Params, MOD).

post(Url, ExHeaders, Params, MOD = ?HTTPC_MOD) ->
    post(Url, ExHeaders, Params, ?CONTENT_TYPE, MOD).

post(Url, ExHeaders, Params, ContentType, MOD = ?HTTPC_MOD) when is_list(ExHeaders) and
                                                                 is_list(Params) ->
    post_(Url, ExHeaders, ContentType, construct_body(ContentType, Params), MOD).

post_(Url, ExHeaders, ContentType, Body, ?HTTPC_HDR(Headers)) ->
    request(post, genrequest(Url, merge_opts(Headers, ExHeaders), ContentType, Body), [], []).

%%--------------------------------------------------------------------
%% HTTP Utils
%%--------------------------------------------------------------------

basic_auth(Username, Password) ->
    {"Authorization", "Basic " ++ base64:encode_to_string(Username ++ ":" ++ Password)}.

%%--------------------------------------------------------------------
%% HTTP Request
%%--------------------------------------------------------------------

request(Method, Request, HTTPOptions, Options) ->
    request(Method, Request, HTTPOptions, Options, 0).

request(Method, Request, HTTPOptions, Options, Times) ->
    case httpc:request(Method, Request, HTTPOptions, Options) of
        %% XXX: a famous of bug on highly QPS
        %% https://github.com/phoenixframework/phoenix/issues/1478
        {error, socket_closed_remotely} when Times < 5 -> request(Method, Request, HTTPOptions, Options, Times+1);
        {error, Reason} -> {error, Reason};
        {ok, {{_Ver, Code, _CodeDesc}, Headers, Body}} ->
            {ok, Code, tune_body(get_value("content-type", Headers), Body)}
    end.

genrequest(Url, Headers) ->
    {Url, Headers}.

genrequest(Url, Headers, ContentType, Body) ->
    {Url, Headers, ContentType, Body}.

merge_opts(Defaults, Options) ->
    lists:foldl(
        fun({Opt, Val}, Acc) ->
                case lists:keymember(Opt, 1, Acc) of
                    true  -> lists:keyreplace(Opt, 1, Acc, {Opt, Val});
                    false -> [{Opt, Val}|Acc]
                end;
            (Opt, Acc) ->
                case lists:member(Opt, Acc) of
                    true  -> Acc;
                    false -> [Opt | Acc]
                end
    end, Defaults, Options).

%%--------------------------------------------------------------------
%% Params Encode
%%--------------------------------------------------------------------

param_uri(Url, QueryStrings) ->
    Url ++ "?" ++ urlencode(QueryStrings).

urlencode(Params) -> urlencode_(Params, []).

urlencode_([], Acc) -> lists:flatten(lists:join("&", lists:reverse(Acc)));
urlencode_([{Key, Value} | L], Acc) ->
    urlencode_(L, [http_uri:encode(to_string(Key)) ++ "=" ++ 
                   http_uri:encode(to_string(Value)) | Acc]).

%%--------------------------------------------------------------------
%% Format Convert
%%--------------------------------------------------------------------

to_string(V) when is_integer(V) -> integer_to_list(V);
to_string(V) when is_binary(V) -> binary_to_list(V);
to_string(V) when is_atom(V) -> atom_to_list(V);
to_string(V) when is_list(V) -> V.

to_json(V) -> jsx:encode(V).

tune_body(ContentType, Body) ->
    case lists:member("application/json", string:tokens(string:to_lower(ContentType), ";")) of
        true ->
            case catch jsx:decode(list_to_binary(Body)) of
                {'EXIT',{badarg,_}} -> Body;
                Result -> Result
            end;
        false -> Body
    end.

construct_body("application/json", Params) -> to_json(Params);
construct_body("application/x-www-form-urlencoded", Params) -> urlencode(Params).

