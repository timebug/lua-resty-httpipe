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

      local ok, err = hp:request("127.0.0.1", 9090, {
                                     method = "GET", path = "/echo" })
      if not ok then
          ngx.log(ngx.ERR, "failed to request: ", err)
          return ngx.exit(503)
      end

      local res, err = hp:receive()
      if not res then
          ngx.log(ngx.ERR, "failed to receive: ", err)
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

      local hp, err = httpipe:new(nil, 10) -- chunk_size = 10
      if not hp then
          ngx.log(ngx.ERR, "failed to new httpipe: ", err)
          return ngx.exit(503)
      end

      hp:set_timeout(5 * 1000) -- 5 sec

      local ok, err = hp:request("127.0.0.1", 9090, {
                                     method = "GET", path = "/echo" })
      if not ok then
          ngx.log(ngx.ERR, "failed to request: ", err)
          return ngx.exit(503)
      end

      -- streaming parser

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

      local from, err = httpipe:new()

      from:set_timeout(5 * 1000) -- 5 sec

      local ok, err = from:request("127.0.0.1", 9090, {
                                       method = "GET", path = "/echo" })

      local res0, err = from:receive{
          header_filter = function (status, headers)
              if status == 200 then
                  return 1
              end
      end }

      -- from one http stream to another, just like a unix pipe
      local to, err = httpipe:new()

      to:set_timeout(5 * 1000) -- 5 sec

      local headers = {
          ["Content-Length"] = res0.headers["Content-Length"]
      }

      local ok, err = to:request("127.0.0.1", 9090, {
                                     method = "POST", path = "/echo",
                                     headers = headers })

      local res1, err = from:receive{
          body_filter = function (chunk)
              local bytes, err = to:write(chunk)
              if err then
                  ngx.log(ngx.WARN, "failed to write err: ", err)
                  return 1
              end
          end
      }

      local res2, err = to:receive()

      ngx.status = res2.status

      for k, v in pairs(res2.headers) do
          ngx.header[k] = v
      end

      ngx.say(res2.body)
    ';
  }
  
}
````

A typical output of the `/simple` location defined above is:

```
GET /echo HTTP/1.1
Host: 127.0.0.1
User-Agent: Resty/HTTPipe-0.03
Accept: */*

```

A typical output of the `/generic` location defined above is:

```
read: ["statusline","200"]
read: ["header",["Server","openresty\/1.5.11.1","Server: openresty\/1.5.11.1"]]
read: ["header",["Date","Sat, 19 Apr 2014 11:04:00 GMT","Date: Sat, 19 Apr 2014 11:04:00 GMT"]]
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
read: ["body","pe-0.03\r\nA"]
read: ["body","ccept: *\/*"]
read: ["body","\r\n\r\n"]
read: ["body_end"]
read: ["eof"]
```

A typical output of the `/advanced` location defined above is:

```
POST /echo HTTP/1.1
Content-Length: 84
User-Agent: Resty/HTTPipe-0.03
Accept: */*
Host: 127.0.0.1

GET /echo HTTP/1.1
Host: 127.0.0.1
User-Agent: Resty/HTTPipe-0.03
Accept: */*


```

# Connection

## new

`syntax: hp, err = httpipe:new(sock?, chunk_size?)`

Creates the httpipe object. In case of failures, returns `nil` and a string describing the error.

The first optional argument, `sock`, can be used to specify the readable TCP socket for response parsing, such as `ngx.req.socket`. With it, you do not need to call `reqeust` method any more.

The second optional argument, `chunk_size`, specifies the buffer size used by cosocket reading operations. Defaults to `8192`.

## set_timeout

`syntax: hp:set_timeout(time)`

Sets the timeout (in ms) protection for subsequent operations, including the `connect` method.

## close

`syntax: ok, err = hp:close(force?)`

Normally, it will call `hp:close()` method automatically after processing the request.

When HTTP/1.1 request without `Connection: close` header or HTTP/1.0 with `Connection: keep-alive` header, `hp:close()` method will call `sock:set_keepalive` immediately puts the current connection into the ngx_lua cosocket connection pool; Otherwise, it will call `sock:close()` to close the connection.

Requests cannot release the connection back to the pool unless you consume all the data or call `hp:close(1)` to close the connection forcibly.

In case of success, returns 1. In case of errors, returns nil with a string describing the error.

# Requesting

## request

`syntax: ok, err = hp:request(host, port, opts?)`

The `opts` table accepts the following fields:

* `version`: Sets the HTTP version. Use `0` for HTTP/1.0 and `1` for HTTP/1.1. Defaults to `1`.
* `method`: The HTTP method string. Defaults to `GET`.
* `path`: The path string. Default to `/`.
* `query`: Specifies query parameters. Accepts either a string or a Lua table.
* `headers`: A table of request headers. Accepts a Lua table.
* `body`: The request body as a string.
* `timeout`: Sets the timeout in milliseconds for network operations. Defaults to `5000`.
* `read_timeout`: Sets the timeout in milliseconds for network read operations specially.
* `send_timeout`: Sets the timeout in milliseconds for network send operations specially.

In case of success, returns 1. In case of errors, returns nil with a string describing the error.

## receive

`syntax: local res, err = hp:receive(callback?)`

The `callback` table accepts the following fields:

* `header_filter`: A callback function for response headers filter

````lua
local res, err = from:receive{
    header_filter = function (status, headers)
        if status == 200 then
        	return 1
        end
end }
````

* `body_filter`: A callback function for response body filter

````lua
local res1, err = hp:receive{
    header_filter = function (chunk)
        ngx.print(chunk)
    end
}
````

**Note** When `return 1	` in callback function，receive process will be interrupted.

Returns a `res` object containing three attributes:

* `res.status` (number)
: The resonse status, e.g. 200
* `res.headers` (table)
: A Lua table with response headers. 
* `res.body` (string)
: The plain response body
* `res.eof` (int)
: If `res.eof == 1` indicate already consume all the data; Otherwise, the request there is still no end, you need call `hp:close(1)` to close the connection forcibly.

**Note** All headers (request and response) are noramlized for
capitalization - e.g., Accept-Encoding, ETag, Foo-Bar, Baz - in the
normal HTTP "standard."

In case of errors, returns nil with a string describing the error.

## read

`syntax: local typ, res, err = hp:read()` 

Streaming parser for the response data.

The user just needs to call the read method repeatedly until a nil token type is returned. For each token returned from the read method, just check the first return value for the current token type. The token type can be `statusline`, `header`, `header_end`, `body`, `body_end` and `eof`. About the format of `res` value, please refer to the above example. For example, several body tokens holding each body data chunk, so `res` value is equal to the body data chunk.

In case of errors, returns nil with a string describing the error.

## write

`syntax: local bytes, err = hp:write(chunk)`

Sends data without blocking on the current httpipe connection.

This method is a synchronous operation that will not return until all the data has been flushed into the system socket send buffer or an error occurs.

In case of success, it returns the total number of bytes that have been sent. Otherwise, it returns nil and a string describing the error.

# Author

Monkey Zhang <timebug.info@gmail.com>

Originally started life based on https://github.com/bakins/lua-resty-http-simple.

The part of the interface design inspired from https://github.com/agentzh/lua-resty-upload.

Cosocket docs and implementation borrowed from the other lua-resty-* cosocket modules.

# Licence

This module is licensed under the 2-clause BSD license.

Copyright (c) 2014, Monkey Zhang <timebug.info@gmail.com>

All rights reserved.

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

* Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.

* Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
