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

no_long_string();
#no_diff();

run_tests();

__DATA__
=== TEST 1: ngx.var.request_uri.
--- http_config eval: $::HttpConfig
--- config
    location /abc {
        content_by_lua '
            local httpipe = require "resty.httpipe"
            local hp = httpipe:new()

            hp:set_timeout(5000)

            local res, err = hp:request("127.0.0.1", ngx.var.server_port, {
                method = "GET",
                path = "/def" .. ngx.var.request_uri,
            })

            ngx.print(res.body)
        ';
    }
    location /def {
        content_by_lua '
            ngx.say(ngx.var.request_uri)
        ';
    }
--- request
GET /abc/中文/测试.txt
--- response_body
/def/abc/中文/测试.txt
--- no_error_log
[error]
[warn]


=== TEST 2: ngx.var.request_uri + escape.
--- http_config eval: $::HttpConfig
--- config
    location /abc {
        content_by_lua '
            local httpipe = require "resty.httpipe"
            local hp = httpipe:new()

            hp:set_timeout(5000)

            local res, err = hp:request("127.0.0.1", ngx.var.server_port, {
                method = "GET",
                path = "/def" .. ngx.var.request_uri,
            })

            ngx.print(res.body)
        ';
    }
    location /def {
        content_by_lua '
            ngx.say(ngx.var.request_uri)
        ';
    }
--- request
GET /abc/%E4%B8%AD%E6%96%87/%E6%B5%8B%E8%AF%95.txt
--- response_body
/def/abc/%E4%B8%AD%E6%96%87/%E6%B5%8B%E8%AF%95.txt
--- no_error_log
[error]
[warn]


=== TEST 3: ngx.var.uri + ngx.escape_uri.
--- http_config eval: $::HttpConfig
--- config
    location /abc {
        content_by_lua '
            local httpipe = require "resty.httpipe"
            local hp = httpipe:new()

            hp:set_timeout(5000)

            local escape_path = function (path)
                local s = string.gsub(path, "([^/]+)", function (s)
                    return ngx.escape_uri(s)
                end)
                return s
            end

            local res, err = hp:request("127.0.0.1", ngx.var.server_port, {
                method = "GET",
                path = "/def" .. escape_path(ngx.var.uri),
            })

            local ver = ngx.config.nginx_version
            if ver >= 1007004 then
                if res.body == "/def/abc/%E4%B8%AD%E6%96%87/%E6%B5%8B%E8%AF%95.txt" then
                    ngx.say("ok")
                else
                    ngx.say("err")
                end
            else
                if res.body == "/def/abc/%e4%b8%ad%e6%96%87/%e6%b5%8b%e8%af%95.txt" then
                    ngx.say("ok")
                else
                    ngx.say("err")
                end
            end
        ';
    }
    location /def {
        content_by_lua '
            ngx.print(ngx.var.request_uri)
        ';
    }
--- request
GET /abc/中文/测试.txt
--- response_body
ok
--- no_error_log
[error]
[warn]


=== TEST 4: ngx.var.uri + ngx.escape_uri + escape.
--- http_config eval: $::HttpConfig
--- config
    location /abc {
        content_by_lua '
            local httpipe = require "resty.httpipe"
            local hp = httpipe:new()

            hp:set_timeout(5000)

            local escape_path = function (path)
                local s = string.gsub(path, "([^/]+)", function (s)
                    return ngx.escape_uri(s)
                end)
                return s
            end

            local res, err = hp:request("127.0.0.1", ngx.var.server_port, {
                method = "GET",
                path = "/def" .. escape_path(ngx.var.uri),
            })

            local ver = ngx.config.nginx_version
            if ver >= 1007004 then
                if res.body == "/def/abc/%E4%B8%AD%E6%96%87/%E6%B5%8B%E8%AF%95.txt" then
                    ngx.say("ok")
                else
                    ngx.say("err")
                end
            else
                if res.body == "/def/abc/%e4%b8%ad%e6%96%87/%e6%b5%8b%e8%af%95.txt" then
                    ngx.say("ok")
                else
                    ngx.say("err")
                end
            end
        ';
    }
    location /def {
        content_by_lua '
            ngx.print(ngx.var.request_uri)
        ';
    }
--- request
GET /abc/%E4%B8%AD%E6%96%87/%E6%B5%8B%E8%AF%95.txt
--- response_body
ok
--- no_error_log
[error]
[warn]
