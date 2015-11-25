# vim:set ft= ts=4 sw=4 et:

use Test::Nginx::Socket;
use Cwd qw(cwd);
use Test::Nginx::Socket 'no_plan';

my $pwd = cwd();

our $HttpConfig = qq{
    lua_package_path "$pwd/lib/?.lua;;";
};

$ENV{TEST_NGINX_RESOLVER} = '8.8.8.8';

no_long_string();
#no_diff();

run_tests();

__DATA__
=== TEST 1: Chunked streaming body reader returns the right content length.
--- http_config eval: $::HttpConfig
--- config
    location = /a {
        content_by_lua '
            local httpipe = require "resty.httpipe"
            local hp = httpipe:new()

            local res, err = hp:request("127.0.0.1", ngx.var.server_port, {
                path = "/b",
                stream = true,
            })

            local chunks = {}
            repeat
                local chunk = res.body_reader()
                if chunk then
                    table.insert(chunks, chunk)
                end
            until not chunk

            local body = table.concat(chunks)
            ngx.say(#body)
            ngx.say(res.headers["Transfer-Encoding"])
            ngx.say(res.headers["Content-Length"])
            ngx.say(res.headers["Connection"])
        ';
    }
    location = /b {
        content_by_lua '
            for j=1,3 do
                local t = {}
                for i=1,10000 do
                    t[i] = 0
                end
                ngx.print(table.concat(t))
            end

            local t = {}
            local len = 2768
            for i=1,len do
                t[i] = 0
            end
            ngx.print(table.concat(t))
        ';
    }
--- request
GET /a
--- response_body
32768
chunked
nil
keep-alive
--- no_error_log
[error]
[warn]


=== TEST 2: Non-Chunked streaming body reader returns the right content length.
--- http_config eval: $::HttpConfig
--- config
    location = /a {
        content_by_lua '
            local httpipe = require "resty.httpipe"
            local hp = httpipe:new()

            local res, err = hp:request("127.0.0.1", ngx.var.server_port, {
                path = "/b",
                stream = true,
            })

            local chunks = {}
            local size = 8192
            repeat
                local chunk = res.body_reader(size)
                if chunk then
                    table.insert(chunks, chunk)
                end
                size = size + size
            until not chunk

            local body = table.concat(chunks)
            ngx.say(#body)
            ngx.say(res.headers["Transfer-Encoding"])
            ngx.say(res.headers["Content-Length"])
            ngx.say(res.headers["Connection"])
            ngx.say(#chunks)
        ';
    }
    location = /b {
        chunked_transfer_encoding off;
        content_by_lua '
            local len = 32768
            local t = {}
            for i=1,len do
                t[i] = 0
            end
            ngx.print(table.concat(t))
        ';
    }
--- request
GET /a
--- response_body
32768
nil
nil
close
3
--- no_error_log
[error]
[warn]


=== TEST 3: Request reader correctly reads body
--- http_config eval: $::HttpConfig
--- config
    location = /a {
        lua_need_request_body off;
        content_by_lua '
            local httpipe = require "resty.httpipe"
            local hp = httpipe:new()

            local reader, err = hp:get_client_body_reader()

            repeat
                local chunk, err = reader()
                if chunk then
                    ngx.print(chunk)
                end
            until chunk == nil

        ';
    }

--- request
POST /a
foobarbazfoobarbazfoobarbazfoobarbazfoobarbazfoobarbazfoobarbazfoobarbazfoobarbazfoobarbazfoobarbazfoobarbaz
--- response_body: foobarbazfoobarbazfoobarbazfoobarbazfoobarbazfoobarbazfoobarbazfoobarbazfoobarbazfoobarbazfoobarbazfoobarbaz
--- no_error_log
[error]
[warn]


=== TEST 4: Request reader correctly reads body in chunks
--- http_config eval: $::HttpConfig
--- config
    location = /a {
        lua_need_request_body off;
        content_by_lua '
            local httpipe = require "resty.httpipe"
            local hp = httpipe:new()

            local reader, err = hp:get_client_body_reader(64)

            local chunks = 0
            repeat
                chunks = chunks +1
                local chunk, err = reader()
                if chunk then
                    ngx.print(chunk)
                end
            until chunk == nil
            ngx.say("\\n"..chunks)
        ';
    }

--- request
POST /a
foobarbazfoobarbazfoobarbazfoobarbazfoobarbazfoobarbazfoobarbazfoobarbazfoobarbazfoobarbazfoobarbazfoobarbaz
--- response_body
foobarbazfoobarbazfoobarbazfoobarbazfoobarbazfoobarbazfoobarbazfoobarbazfoobarbazfoobarbazfoobarbazfoobarbaz
3
--- no_error_log
[error]
[warn]


=== TEST 5: Request reader passes into client
--- http_config eval: $::HttpConfig
--- config
    location = /a {
        lua_need_request_body off;
        content_by_lua '
            local httpipe = require "resty.httpipe"
            local hp = httpipe:new()

            local reader, err = hp:get_client_body_reader(64)

            local res, err = hp:request("127.0.0.1", ngx.var.server_port, {
                method = POST,
                path = "/b",
                body = reader,
                headers = ngx.req.get_headers(100, true),
            })

            ngx.say(res.body)
        ';
    }

    location = /b {
        content_by_lua '
            ngx.req.read_body()
            local body, err = ngx.req.get_body_data()
            ngx.print(body)
        ';
    }

--- request
POST /a
foobarbazfoobarbazfoobarbazfoobarbazfoobarbazfoobarbazfoobarbazfoobarbazfoobarbazfoobarbazfoobarbazfoobarbaz
--- response_body
foobarbazfoobarbazfoobarbazfoobarbazfoobarbazfoobarbazfoobarbazfoobarbazfoobarbazfoobarbazfoobarbazfoobarbaz
--- no_error_log
[error]


=== TEST 6: Body reader is a function returning nil when no body is present.
--- http_config eval: $::HttpConfig
--- config
    location = /a {
        content_by_lua '
            local httpipe = require "resty.httpipe"
            local hp = httpipe:new()

            local res, err = hp:request("127.0.0.1", ngx.var.server_port, {
                path = "/b",
                method = "HEAD",
                stream = true,
            })

            repeat
                local chunk = res.body_reader()
            until not chunk
        ';
    }
    location = /b {
        content_by_lua '
            ngx.exit(200)
        ';
    }
--- request
GET /a
--- no_error_log
[error]
[warn]


=== TEST 7: Non-Chunked Streaming body reader with Content-Length response header.
--- http_config eval: $::HttpConfig
--- config
    location = /a {
        content_by_lua '
            local httpipe = require "resty.httpipe"
            local hp = httpipe:new()

            local res, err = hp:request("127.0.0.1", ngx.var.server_port, {
                path = "/b",
                stream = true,
            })

            local chunks = {}
            repeat
                local chunk = res.body_reader()
                if chunk then
                    table.insert(chunks, chunk)
                end
            until not chunk

            local body = table.concat(chunks)
            ngx.say(#body)
            ngx.say(res.headers["Transfer-Encoding"])
            ngx.say(res.headers["Content-Length"])
            ngx.say(res.headers["Connection"])
        ';
    }
    location = /b {
        content_by_lua '
            ngx.header["Content-Length"] = 32768
            for j=1,3 do
                local t = {}
                for i=1,10000 do
                    t[i] = 0
                end
                ngx.print(table.concat(t))
            end

            local t = {}
            local len = 2768
            for i=1,len do
                t[i] = 0
            end
            ngx.print(table.concat(t))
        ';
    }
--- request
GET /a
--- response_body
32768
nil
32768
keep-alive
--- no_error_log
[error]
[warn]
