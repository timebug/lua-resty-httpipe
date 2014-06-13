# vim:set ft= ts=4 sw=4 et:

use Test::Nginx::Socket;
use Cwd qw(cwd);

plan tests => repeat_each() * (blocks() * 4);

my $pwd = cwd();

our $HttpConfig = qq{
    lua_package_path "$pwd/lib/?.lua;;";
    error_log logs/error.log debug;
};

$ENV{TEST_NGINX_RESOLVER} = '8.8.8.8';

no_long_string();
#no_diff();

run_tests();

__DATA__
=== TEST 1: Header filter.
--- http_config eval: $::HttpConfig
--- config
    location = /a {
        content_by_lua '
            local httpipe = require "resty.httpipe"
            local hp = httpipe:new()

            hp:set_timeout(5000)

            local ok, err = hp:connect("127.0.0.1", ngx.var.server_port)

            local ok, err = hp:send_request{
                method = "GET",
                path = "/b",
            }

            local res, err = hp:read_response{
                header_filter = function (status, headers)
                    headers["X-Test-A"] = nil
                end
            }

            ngx.status = res.status
            ngx.say(res.headers["X-Test-A"])
            ngx.say(res.headers["X-Test-B"])
            ngx.say(res.body)
        ';
    }
    location = /b {
        content_by_lua '
            ngx.header["X-Test-A"] = "x-value-a"
            ngx.header["X-Test-B"] = "x-value-b"
            ngx.print("OK")
        ';
    }
--- request
GET /a
--- response_body
nil
x-value-b
OK
--- no_error_log
[error]
[warn]


=== TEST 2: Body filter.
--- http_config eval: $::HttpConfig
--- config
    location = /a {
        content_by_lua '
            local httpipe = require "resty.httpipe"
            local h0 = httpipe:new(5)

            h0:set_timeout(5000)

            local r0, err = h0:request("127.0.0.1", ngx.var.server_port, {
                method = "GET",
                path = "/b",
                stream = true
            })

            local h1 = httpipe:new()

            h1:set_timeout(5000)

            local headers = {
                ["Content-Length"] = r0.headers["Content-Length"]
            }

            local r1, err = h1:request("127.0.0.1", ngx.var.server_port, {
                method = "POST",
                path = "/c",
                headers = headers,
                body = r0.body_reader
            })

            ngx.status = r1.status
            ngx.say(#r1.body)
        ';
    }
    location = /b {
        content_by_lua '
            local t = {}
            local chunksize = 1024
            for i=1, chunksize do
                t[i] = 1
            end
            ngx.header.content_length = chunksize
            ngx.print(table.concat(t))
        ';
    }
    location = /c {
        content_by_lua '
            ngx.req.read_body()
            local body, err = ngx.req.get_body_data()
            if #body == 1024 then
                local t = {}
                for i=1, 32768 do
                    t[i] = 0
                end
                ngx.print(table.concat(t))
             else
                ngx.log(ngx.ERR, "failed")
             end
        ';
    }
--- request
GET /a
--- response_body
32768
--- no_error_log
[error]
[warn]


=== TEST 3: HTTP Pipe.
--- http_config eval: $::HttpConfig
--- config
    location = /a {
        content_by_lua '
            local httpipe = require "resty.httpipe"
            local hp = httpipe:new(5)

            hp:set_timeout(5000)

            local r0, err = hp:request("127.0.0.1", ngx.var.server_port, {
                method = "GET",
                path = "/b",
                stream = true
            })

            local pipe = r0.pipe

            pipe:set_timeout(5000)

            local r1, err = pipe:request("127.0.0.1", ngx.var.server_port, {
                method = "POST",
                path = "/c"
            })

            ngx.status = r1.status
            ngx.say(#r1.body)
        ';
    }
    location = /b {
        content_by_lua '
            local t = {}
            local chunksize = 1024
            for i=1, chunksize do
                t[i] = 1
            end
            ngx.header.content_length = chunksize
            ngx.print(table.concat(t))
        ';
    }
    location = /c {
        content_by_lua '
            ngx.req.read_body()
            local body, err = ngx.req.get_body_data()
            if #body == 1024 then
                local t = {}
                for i=1, 32768 do
                    t[i] = 0
                end
                ngx.print(table.concat(t))
             else
                ngx.log(ngx.ERR, "failed")
             end
        ';
    }
--- request
GET /a
--- response_body
32768
--- no_error_log
[error]
[warn]
