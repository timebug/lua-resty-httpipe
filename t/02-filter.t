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

            local ok, err = hp:request("127.0.0.1", ngx.var.server_port, {
                method = "GET",
                path = "/b"
            })

            local res, err = hp:receive{
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


=== TEST 2: Body filter.
--- http_config eval: $::HttpConfig
--- config
    location = /a {
        content_by_lua '
            local httpipe = require "resty.httpipe"
            local from = httpipe:new(nil, 5)

            from:set_timeout(5000)

            local ok, err = from:request("127.0.0.1", ngx.var.server_port, {
                method = "GET",
                path = "/b"
            })

            local res0, err = from:receive{
                header_filter = function (status, headers)
                    if status == 200 then
                        return 1
                    end
            end }

            local to = httpipe:new()

            to:set_timeout(5000)

            local headers = {
                ["Content-Length"] = res0.headers["Content-Length"]
            }
            local ok, err = to:request("127.0.0.1", ngx.var.server_port, {
                method = "POST",
                path = "/c",
                headers = headers,
            })

            local res1, err = from:receive{
                body_filter = function (chunk)
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
                ngx.log(ngx.ERROR, "failed")
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
