# httpc2

A helper of httpc

## Usage

Make a GET request:
```erl
M = httpc:new().

M:get("http://baidu.com").

M:get("http://baidu.com", [{username, "aname"}]).
```

Make a POST request:
```erl
M = httpc:new().

%% Default encode post params with 'application/json'
M:post("http://somehost.com", [{param1, value}]).
```

## TODO
- Support PUT, DELETE, etc.

