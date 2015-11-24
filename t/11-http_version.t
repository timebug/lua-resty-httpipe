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
=== TEST 1: HTTP 1.1.
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

            ngx.say(res.headers["X-Foo"])
            ngx.say(res.headers["Connection"])
            ngx.say(res.body)
        ';
    }
    location = /b {
        content_by_lua '
            ngx.header["X-Foo"] = ngx.req.get_headers()["Connection"]
            ngx.print(ngx.req.http_version() * 10)
        ';
    }
--- request
GET /a
--- response_body
nil
keep-alive
11
--- no_error_log
[error]
[warn]


=== TEST 2: HTTP 1.0.
--- http_config eval: $::HttpConfig
--- config
    location = /a {
        content_by_lua '
            local httpipe = require "resty.httpipe"
            local hp = httpipe:new()

            hp:set_timeout(5000)

            local res, err = hp:request("127.0.0.1", ngx.var.server_port, {
                version = 10,
                method = "GET",
                path = "/b"
            })

            ngx.say(res.headers["X-Foo"])
            ngx.say(res.headers["Connection"])
            ngx.say(res.body)
        ';
    }
    location = /b {
        content_by_lua '
            ngx.header["X-Foo"] = ngx.req.get_headers()["Connection"]
            ngx.print(ngx.req.http_version() * 10)
        ';
    }
--- request
GET /a
--- response_body
keep-alive
keep-alive
10
--- no_error_log
[error]
[warn]


=== TEST 3: HTTP 0.9.
--- http_config eval: $::HttpConfig
--- config
    location = /a {
        content_by_lua '
            local httpipe = require "resty.httpipe"
            local hp = httpipe:new()

            hp:set_timeout(5000)

            local res, err = hp:request("127.0.0.1", ngx.var.server_port, {
                version = 9,
                method = "GET",
                path = "/b"
            })

            ngx.say(err)
        ';
    }
    location = /b {
        content_by_lua '
            ngx.print(ngx.req.http_version() * 10)
        ';
    }
--- request
GET /a
--- response_body
unknown HTTP version
--- no_error_log
[error]
[warn]


=== TEST 4: HTTP 1.1 + close.
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
                headers = { ["Connection"] = "close" },
            })

            ngx.say(res.headers["X-Foo"])
            ngx.say(res.headers["Connection"])
            ngx.say(res.body)
        ';
    }
    location = /b {
        content_by_lua '
            ngx.header["X-Foo"] = ngx.req.get_headers()["Connection"]
            ngx.print(ngx.req.http_version() * 10)
        ';
    }
--- request
GET /a
--- response_body
close
close
11
--- no_error_log
[error]
[warn]


=== TEST 5: HTTP 1.0 + close.
--- http_config eval: $::HttpConfig
--- config
    location = /a {
        content_by_lua '
            local httpipe = require "resty.httpipe"
            local hp = httpipe:new()

            hp:set_timeout(5000)

            local res, err = hp:request("127.0.0.1", ngx.var.server_port, {
                version = 10,
                method = "GET",
                path = "/b",
                headers = { ["Connection"] = "close" },
            })

            ngx.say(res.headers["X-Foo"])
            ngx.say(res.headers["Connection"])
            ngx.say(res.body)
        ';
    }
    location = /b {
        content_by_lua '
            ngx.header["X-Foo"] = ngx.req.get_headers()["Connection"]
            ngx.print(ngx.req.http_version() * 10)
        ';
    }
--- request
GET /a
--- response_body
close
close
10
--- no_error_log
[error]
[warn]


=== TEST 6: HTTP 1.1 + default.
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
                headers = { ["Connection"] = "default" },
            })

            ngx.say(res.headers["X-Foo"])
            ngx.say(res.headers["Connection"])
            ngx.say(res.body)
        ';
    }
    location = /b {
        content_by_lua '
            ngx.header["X-Foo"] = ngx.req.get_headers()["Connection"]
            ngx.print(ngx.req.http_version() * 10)
        ';
    }
--- request
GET /a
--- response_body
default
keep-alive
11
--- no_error_log
[error]
[warn]


=== TEST 7: HTTP 1.0 + default.
--- http_config eval: $::HttpConfig
--- config
    location = /a {
        content_by_lua '
            local httpipe = require "resty.httpipe"
            local hp = httpipe:new()

            hp:set_timeout(5000)

            local res, err = hp:request("127.0.0.1", ngx.var.server_port, {
                version = 10,
                method = "GET",
                path = "/b",
                headers = { ["Connection"] = "default" },
            })

            ngx.say(res.headers["X-Foo"])
            ngx.say(res.headers["Connection"])
            ngx.say(res.body)
        ';
    }
    location = /b {
        content_by_lua '
            ngx.header["X-Foo"] = ngx.req.get_headers()["Connection"]
            ngx.print(ngx.req.http_version() * 10)
        ';
    }
--- request
GET /a
--- response_body
default
close
10
--- no_error_log
[error]
[warn]
