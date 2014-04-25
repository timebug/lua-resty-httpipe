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
            local http = require "resty.httpipe"
            local httpc = http:new()
            httpc:set_timeout(5000)
            local ok, err = httpc:request("127.0.0.1", ngx.var.server_port, {
                method = "GET",
                path = "/b"
            })

            local res, err = httpc:receive{
                header_filter = function (status, headers)
                    headers["X-Test-A"] = nil
                end
            }
            ngx.status = res.status
            ngx.say(res.headers["X-Test-A"])
            ngx.say(res.headers["X-Test-B"])
        ';
    }
    location = /b {
        content_by_lua '
            ngx.header["X-Test-A"] = "x-value-a"
            ngx.header["X-Test-B"] = "x-value-b"
            ngx.say("OK")
        ';
    }
--- request
GET /a
--- response_body
nil
x-value-b
--- no_error_log
[error]
[warn]


=== TEST 2: body filter.
--- http_config eval: $::HttpConfig
--- config
    location = /a {
        content_by_lua '
            local http = require "resty.httpipe"

            local from = http:new()
            from:set_timeout(5000)
            local ok, err = from:request("127.0.0.1", ngx.var.server_port, {
                method = "GET",
                path = "/b"
            })

            local to = http:new()
            to:set_timeout(5000)
            local headers = {
                ["Content-Length"] = 100
            }
            local ok, err = to:request("127.0.0.1", ngx.var.server_port, {
                method = "POST",
                path = "/b",
                headers = headers,
            })

            local res1, err = from:receive{
                body_filter = function(chunk)
                    to:write(chunk)
                end
            }

            local res2, err = to:receive()

            ngx.status = res2.status
            ngx.say(#res2.body)
        ';
    }
    location = /b {
        content_by_lua '
            local t = {}
            for i=1, 32768 do
                t[i] = 0
            end
            ngx.print(table.concat(t))
        ';
    }
--- request
GET /a
--- response_body
32768
--- no_error_log
[error]
[warn]

