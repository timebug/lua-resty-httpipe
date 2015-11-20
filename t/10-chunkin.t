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
=== TEST 1: Chunked-Encoding request body support
--- http_config eval: $::HttpConfig
--- config
    location = /a {
        content_by_lua '
            local httpipe = require "resty.httpipe"
            local hp0 = httpipe:new()

            local r0, err = hp0:request("127.0.0.1", ngx.var.server_port, {
                path = "/b",
                stream = true,
            })
            ngx.say(r0.status)
            ngx.say(r0.headers["Transfer-Encoding"])

            local hp1 = httpipe:new()
            local r1, err = hp1:request("127.0.0.1", ngx.var.server_port, {
                method = "POST", path = "/c",
                body = r0.body_reader,
            })

            ngx.say(r1.status)
            ngx.say(r1.headers["Transfer-Encoding"])
            ngx.say(#r1.body)
        ';
    }
    location = /b {
        content_by_lua '
            for j=1,6 do
                local t = {}
                for i=1, math.pow(3, j) do
                    t[i] = "a"
                end
                ngx.print(table.concat(t))
            end
        ';
    }
    location = /c {
        content_by_lua '
            ngx.req.read_body()
            local body, err = ngx.req.get_body_data()
            ngx.print(body)
        ';
    }
--- request
GET /a
--- response_body
200
chunked
200
chunked
1092
--- no_error_log
[error]
[warn]


=== TEST 2: Chunked-Encoding request body support with zero size
--- http_config eval: $::HttpConfig
--- config
    location = /a {
        content_by_lua '
            local httpipe = require "resty.httpipe"
            local hp0 = httpipe:new()

            local r0, err = hp0:request("127.0.0.1", ngx.var.server_port, {
                path = "/b",
                stream = true,
            })
            ngx.say(r0.status)
            ngx.say(r0.headers["Transfer-Encoding"])

            local hp1 = httpipe:new()
            local r1, err = hp1:request("127.0.0.1", ngx.var.server_port, {
                method = "POST", path = "/c",
                body = r0.body_reader,
            })

            ngx.say(r1.status)
            ngx.say(r1.headers["Transfer-Encoding"])
            ngx.say(#r1.body)
        ';
    }
    location = /b {
        content_by_lua '
            ngx.print()
        ';
    }
    location = /c {
        content_by_lua '
            ngx.req.read_body()
            local body, err = ngx.req.get_body_data()
            if not body and not err then
                ngx.print()
            end
        ';
    }
--- request
GET /a
--- response_body
200
chunked
200
chunked
0
--- no_error_log
[error]
[warn]


=== TEST 3: Chunked-Encoding request body support with pipe
--- http_config eval: $::HttpConfig
--- config
    location = /a {
        content_by_lua '
            local httpipe = require "resty.httpipe"
            local hp0 = httpipe:new()

            local r0, err = hp0:request("127.0.0.1", ngx.var.server_port, {
                path = "/b",
                stream = true,
            })
            ngx.say(r0.status)
            ngx.say(r0.headers["Transfer-Encoding"])

            local pipe = r0.pipe
            local r1, err = pipe:request("127.0.0.1", ngx.var.server_port, {
                method = "POST", path = "/c",
            })

            ngx.say(r1.status)
            ngx.say(r1.headers["Transfer-Encoding"])
            ngx.say(#r1.body)
        ';
    }
    location = /b {
        content_by_lua '
            for j=1,6 do
                local t = {}
                for i=1, math.pow(3, j) do
                    t[i] = "a"
                end
                ngx.print(table.concat(t))
            end
        ';
    }
    location = /c {
        content_by_lua '
            ngx.req.read_body()
            local body, err = ngx.req.get_body_data()
            ngx.print(body)
        ';
    }
--- request
GET /a
--- response_body
200
chunked
200
chunked
1092
--- no_error_log
[error]
[warn]
