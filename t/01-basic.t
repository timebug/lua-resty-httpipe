# vim:set ft= ts=4 sw=4 et:

use Test::Nginx::Socket;
use Cwd qw(cwd);
use Test::Nginx::Socket 'no_plan';

my $pwd = cwd();

our $HttpConfig = qq{
    lua_package_path "$pwd/lib/?.lua;;";
    error_log logs/error.log debug;
};

$ENV{TEST_NGINX_RESOLVER} = '8.8.8.8';
$ENV{TEST_NGINX_HTML_DIR} ||= html_dir();
$ENV{TEST_NGINX_PWD} ||= $pwd;

no_long_string();
#no_diff();

run_tests();

__DATA__
=== TEST 1: Simple get.
--- http_config eval: $::HttpConfig
--- config
    location = /a {
        content_by_lua '
            local httpipe = require "resty.httpipe"
            local hp = httpipe:new()

            hp:set_timeout(5000)

            local res, err = hp:request("127.0.0.1", ngx.var.server_port, {
                method = "GET",
                path = "/b"
            })

            ngx.print(res.body)
        ';
    }
    location = /b {
        echo "OK";
    }
--- request
GET /a
--- response_body
OK
--- no_error_log
[error]
[warn]


=== TEST 2: Status code
--- http_config eval: $::HttpConfig
--- config
    location = /a {
        content_by_lua '
            local httpipe = require "resty.httpipe"
            local hp = httpipe:new()

            hp:set_timeout(5000)

            local res, err = hp:request("127.0.0.1", ngx.var.server_port, {
                method = "GET",
                path = "/b"
            })

            ngx.status = res.status
            ngx.print(res.body)
        ';
    }
    location = /b {
        content_by_lua '
            ngx.status = 404
            ngx.say("OK")
        ';
    }
--- request
GET /a
--- response_body
OK
--- error_code: 404
--- no_error_log
[error]
[warn]


=== TEST 3: Response headers
--- http_config eval: $::HttpConfig
--- config
    location = /a {
        content_by_lua '
            local httpipe = require "resty.httpipe"
            local hp = httpipe:new()

            hp:set_timeout(5000)

            local res, err = hp:request("127.0.0.1", ngx.var.server_port, {
                method = "GET",
                path = "/b"
            })

            ngx.status = res.status
            ngx.say(res.headers["X-Test"])

            if type(res.headers["Set-Cookie"]) == "table" then
                ngx.say(table.concat(res.headers["Set-Cookie"], ", "))
            else
                ngx.say(res.headers["Set-Cookie"])
            end

        ';
    }
    location = /b {
        content_by_lua '
            ngx.header["X-Test"] = "x-value"
            ngx.header["Set-Cookie"] = {"a=32; path=/", "b=4; path=/", "c"}
            ngx.say("OK")
        ';
    }
--- request
GET /a
--- response_body
x-value
a=32; path=/, b=4; path=/, c
--- no_error_log
[error]
[warn]


=== TEST 4: Query
--- http_config eval: $::HttpConfig
--- config
    location = /a {
        content_by_lua '
            local httpipe = require "resty.httpipe"
            local hp = httpipe:new()

            hp:set_timeout(5000)

            local res, err = hp:request("127.0.0.1", ngx.var.server_port, {
                method = "GET",
                path = "/b",
                query = {
                    a = 1,
                    b = 2,
                },
            })

            ngx.status = res.status
            for k,v in pairs(res.headers) do
                ngx.header[k] = v
            end
            ngx.say(res.body)
        ';
    }
    location = /b {
        content_by_lua '
            for k,v in pairs(ngx.req.get_uri_args()) do
                ngx.header["X-Header-" .. string.upper(k)] = v
            end
        ';
    }
--- request
GET /a
--- response_headers
X-Header-A: 1
X-Header-B: 2
--- no_error_log
[error]
[warn]


=== TEST 5: HEAD has no body.
--- http_config eval: $::HttpConfig
--- config
    location = /a {
        content_by_lua '
            local httpipe = require "resty.httpipe"
            local hp = httpipe:new()

            hp:set_timeout(5000)

            local res, err = hp:request("127.0.0.1", ngx.var.server_port, {
                method = "HEAD",
                path = "/b"
            })

            ngx.status = res.status
            if res.body then
                ngx.print(res.body)
            end
        ';
    }
    location = /b {
        echo "OK";
    }
--- request
GET /a
--- response_body
--- no_error_log
[error]
[warn]


=== TEST 6: Request without connect.
--- http_config eval: $::HttpConfig
--- config
    location = /a {
        content_by_lua '
            local httpipe = require "resty.httpipe"
            local hp = httpipe:new()

            hp:set_timeout(5000)

            local ok, err = hp:connect("127.0.0.1", ngx.var.server_port)

            local res, err = hp:request{
                method = "GET",
                path = "/b"
            }

            ngx.print(res.body)
        ';
    }
    location = /b {
        echo "OK";
    }
--- request
GET /a
--- response_body
OK
--- no_error_log
[error]
[warn]


=== TEST 7: 304 without Content-Length.
--- http_config eval: $::HttpConfig
--- config
    location = /a {
        content_by_lua '
            local httpipe = require "resty.httpipe"
            local hp = httpipe:new()

            hp:set_timeout(2000)

            local res, err = hp:request("127.0.0.1", ngx.var.server_port, {
                method = "GET",
                path = "/b"
            })

            if not res then
                ngx.header["X-Foo"] = err
                ngx.header["X-Eof"] = tostring(hp:eof())
                return ngx.exit(503)
            end

            ngx.status = res.status
            for k,v in pairs(res.headers) do
                ngx.header[k] = v
            end
            ngx.header["X-Eof"] = tostring(hp:eof())
            return ngx.exit(res.status)
        ';
    }
    location = /b {
        content_by_lua '
            ngx.status = 304
            ngx.header["Content-Length"] = nil
            ngx.header["X-Foo"] = "bar"
            return ngx.exit(ngx.OK)
        ';
    }
--- request
GET /a
--- response_headers
X-Foo: bar
X-Eof: true
--- error_code: 304
--- no_error_log
[error]
[warn]


=== TEST 8: Simple get + Host.
--- http_config eval: $::HttpConfig
--- config
    location = /a {
        content_by_lua '
            local httpipe = require "resty.httpipe"
            local hp = httpipe:new()

            hp:set_timeout(5000)

            local res, err = hp:request("127.0.0.1", ngx.var.server_port, {
                method = "GET",
                path = "/b"
            })

            ngx.print(res.body)
        ';
    }
    location = /b {
        echo $http_host;
    }
--- request
GET /a
--- response_body
127.0.0.1:1984
--- no_error_log
[error]
[warn]


=== TEST 9: Simple get + Unix Socket Host.
--- http_config
    lua_package_path "$TEST_NGINX_PWD/lib/?.lua;;";
    error_log logs/error.log debug;
    server {
        listen unix:/tmp/nginx.sock;
        default_type 'text/plain';
        server_tokens off;

        location = /b {
            echo $http_host;
        }
    }
--- config
    location = /a {
        content_by_lua '
            local httpipe = require "resty.httpipe"
            local hp = httpipe:new()

            hp:set_timeout(5000)

            local res, err = hp:request("unix:/tmp/nginx.sock", {
                method = "GET",
                path = "/b"
            })

            ngx.status = res.status
            ngx.print(res.body)
        ';
    }
--- request
GET /a
--- error_code: 400
--- no_error_log
[error]
[warn]