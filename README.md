# lua-resty-httpipe

Lua HTTP client cosocket driver for [OpenResty](http://openresty.org/) / [ngx_lua](https://github.com/chaoslawful/lua-nginx-module).

# Status

Ready for testing. Probably production ready in most cases, though not yet proven in the wild. Please check the issues list and let me know if you have any problems / questions.

# Features

* HTTP 1.0 and 1.1
* Flexible interface design
* Streaming reader and uploads
* Chunked transfer encoding
* Keepalive

## Synopsis

````lua
lua_package_path "/path/to/lua-resty-httpipe/lib/?.lua;;";

server {

  listen 9090;

  location /echo {
    content_by_lua '
      local raw_header = ngx.req.raw_header()

      if ngx.req.get_method() == "GET" then
          ngx.header["Content-Length"] = #raw_header
      end

      ngx.req.read_body()
      local body, err = ngx.req.get_body_data()

      ngx.print(raw_header)
      ngx.print(body)
    ';
  }

  location /simple {
    content_by_lua '
      local httpipe = require "resty.httpipe"

      local hp, err = httpipe:new()
      if not hp then
          ngx.log(ngx.ERR, "failed to new httpipe: ", err)
          return ngx.exit(503)
      end

      hp:set_timeout(5 * 1000) -- 5 sec

      local res, err = hp:request("127.0.0.1", 9090, {
                                     method = "GET", path = "/echo" })
      if not res then
          ngx.log(ngx.ERR, "failed to request: ", err)
          return ngx.exit(503)
      end

      ngx.status = res.status

      for k, v in pairs(res.headers) do
          ngx.header[k] = v
      end

      ngx.say(res.body)
    ';
  }

  location /generic {
    content_by_lua '
      local cjson = require "cjson"
      local httpipe = require "resty.httpipe"

      local hp, err = httpipe:new(10) -- chunk_size = 10
      if not hp then
          ngx.log(ngx.ERR, "failed to new httpipe: ", err)
          return ngx.exit(503)
      end

      hp:set_timeout(5 * 1000) -- 5 sec

      local res, err = hp:request("127.0.0.1", 9090, {
                                     method = "GET", path = "/echo",
                                     stream = httpipe.FULL })
      if not res then
          ngx.log(ngx.ERR, "failed to request: ", err)
          return ngx.exit(503)
      end

      -- full streaming parser

      while true do
          local typ, res, err = hp:read()
          if not typ then
              ngx.say("failed to read: ", err)
              return
          end

          ngx.say("read: ", cjson.encode({typ, res}))

          if typ == 'eof' then
              break
          end
      end
    ';
  }

  location /advanced {
    content_by_lua '
      local httpipe = require "resty.httpipe"

      local h0, err = httpipe:new()

      h0:set_timeout(5 * 1000) -- 5 sec

      local r0, err = h0:request("127.0.0.1", 9090, {
                                     method = "GET", path = "/echo",
                                     stream = httpipe.BODY })

      -- from one http stream to another, just like a unix pipe

      local h1, err = httpipe:new()

      h1:set_timeout(5 * 1000) -- 5 sec

      local headers = {
          ["Content-Length"] = r0.headers["Content-Length"]
      }

      local r1, err = h1:request("127.0.0.1", 9090, {
                                     method = "POST", path = "/echo",
                                     headers = headers,
                                     body = function () return h0:read_body() end })

      ngx.status = r1.status

      for k, v in pairs(r1.headers) do
          ngx.header[k] = v
      end

      ngx.say(r1.body)
    ';
  }

}
````

A typical output of the `/simple` location defined above is:

```
GET /echo HTTP/1.1
Host: 127.0.0.1
User-Agent: Resty/HTTPipe-0.04
Accept: */*

```

A typical output of the `/generic` location defined above is:

```
read: ["statusline","200"]
read: ["header",["Server","openresty\/1.5.12.1","Server: openresty\/1.5.12.1"]]
read: ["header",["Date","Sat, 07 Jun 2014 07:52:06 GMT","Date: Sat, 07 Jun 2014 07:52:06 GMT"]]
read: ["header",["Content-Type","text\/plain","Content-Type: text\/plain"]]
read: ["header",["Connection","keep-alive","Connection: keep-alive"]]
read: ["header",["Content-Length","84","Content-Length: 84"]]
read: ["header_end"]
read: ["body","GET \/echo "]
read: ["body","HTTP\/1.1\r\n"]
read: ["body","Host: 127."]
read: ["body","0.0.1\r\nUse"]
read: ["body","r-Agent: R"]
read: ["body","esty\/HTTPi"]
read: ["body","pe-0.04\r\nA"]
read: ["body","ccept: *\/*"]
read: ["body","\r\n\r\n"]
read: ["body_end"]
read: ["eof"]
```

A typical output of the `/advanced` location defined above is:

```
POST /echo HTTP/1.1
Content-Length: 84
User-Agent: Resty/HTTPipe-0.04
Accept: */*
Host: 127.0.0.1

GET /echo HTTP/1.1
Host: 127.0.0.1
User-Agent: Resty/HTTPipe-0.04
Accept: */*


```

# Connection

## new

`syntax: hp, err = httpipe:new(chunk_size?)`

Creates the httpipe object. In case of failures, returns `nil` and a string describing the error.

The argument, `chunk_size`, specifies the buffer size used by cosocket reading operations. Defaults to `8192`.

## set_timeout

`syntax: hp:set_timeout(time)`

Sets the timeout (in ms) protection for subsequent operations, including the `connect` method.

## set_keepalive

`syntax: ok, err = hp:set_keepalive(max_idle_timeout, pool_size)`

Attempts to puts the current connection into the ngx_lua cosocket connection pool.

**Note** Normally, it will be called automatically after processing the request. In other words, we cannot release the connection back to the pool unless you consume all the data.

You can specify the max idle timeout (in ms) when the connection is in the pool and the maximal size of the pool every nginx worker process.

In case of success, returns 1. In case of errors, returns nil with a string describing the error.

## get_reused_times

`syntax: times, err = hp:get_reused_times()`

This method returns the (successfully) reused times for the current connection. In case of error, it returns `nil` and a string describing the error.

If the current connection does not come from the built-in connection pool, then this method always returns `0`, that is, the connection has never been reused (yet). If the connection comes from the connection pool, then the return value is always non-zero. So this method can also be used to determine if the current connection comes from the pool.

## close

`syntax: ok, err = hp:close()`

Closes the current connection and returns the status.

In case of success, returns `1`. In case of errors, returns `nil` with a string describing the error.


# Requesting

## request

`syntax: res, err = hp:request(host, port, opts?)`

`syntax: res, err = hp:request("unix:/path/to/unix-domain.socket", opts?)`

The `opts` table accepts the following fields:

* `version`: Sets the HTTP version. Use `0` for HTTP/1.0 and `1` for HTTP/1.1. Defaults to `1`.
* `method`: The HTTP method string. Defaults to `GET`.
* `path`: The path string. Default to `/`.
* `query`: Specifies query parameters. Accepts either a string or a Lua table.
* `headers`: A table of request headers. Accepts a Lua table.
* `body`: The request body as a string, or an iterator function.
* `timeout`: Sets the timeout in milliseconds for network operations. Defaults to `5000`.
* `read_timeout`: Sets the timeout in milliseconds for network read operations specially.
* `send_timeout`: Sets the timeout in milliseconds for network send operations specially.
* `stream`: Specifies special stream mode, `FULL` and `BODY` is currently optional.

Returns a `res` object containing four attributes:

* `res.status` (number)
: The resonse status, e.g. 200
* `res.headers` (table)
: A Lua table with response headers.
* `res.body` (string)
: The plain response body.
* `res.eof` (int)
: If `res.eof` is `true` indicate already consume all the data; Otherwise, the request there is still no end, you need call `hp:close` to close the connection forcibly.

**Note** All headers (request and response) are noramlized for
capitalization - e.g., Accept-Encoding, ETag, Foo-Bar, Baz - in the
normal HTTP "standard."

If the stream specified as `FULL` mode, res is always a empty Lua table. You need to use `hp:response` or `hp:read` method to parse the full response specially.

If the stream specified as `BODY` mode, res containing the parsed `status` and `headers`. You also need to use `hp:read_body` method to read the response body specially.

In case of errors, returns nil with a string describing the error.

## response

`syntax: local res, err = hp:response(callback?)`

The `callback` table accepts the following fields:

* `header_filter`: A callback function for response headers filter

````lua
local res, err = hp:response{
    header_filter = function (status, headers)
        if status == 200 then
        	return 1
        end
end }
````

* `body_filter`: A callback function for response body filter

````lua
local res, err = hp:response{
    body_filter = function (chunk)
        ngx.print(chunk)
    end
}
````

**Note** When `return 1	` in callback function，filter process will be interrupted.

Returns a res object containing four attributes, as same as `hp:request` method.

In case of errors, returns nil with a string describing the error.

## read

`syntax: local typ, res, err = hp:read()`

Streaming parser for the full response.

The user just needs to call the read method repeatedly until a nil token type is returned. For each token returned from the read method, just check the first return value for the current token type. The token type can be `statusline`, `header`, `header_end`, `body`, `body_end` and `eof`. About the format of `res` value, please refer to the above example. For example, several body tokens holding each body data chunk, so `res` value is equal to the body data chunk.

In case of errors, returns nil with a string describing the error.

## read_body

`syntax: local chunk, err = hp:read_body()`

Streaming reader for the response body.

In case of success, it returns the data received; in case of error, it returns nil with a string describing the error.

# Author

Monkey Zhang <timebug.info@gmail.com>, UPYUN Inc.

Originally started life based on https://github.com/bakins/lua-resty-http-simple.

The part of the interface design inspired from https://github.com/agentzh/lua-resty-upload.

Cosocket docs and implementation borrowed from the other lua-resty-* cosocket modules.

# Licence

This module is licensed under the 2-clause BSD license.

Copyright (c) 2014, Monkey Zhang <timebug.info@gmail.com>, UPYUN Inc.

All rights reserved.

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

* Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.

* Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
