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
=== TEST 1: http:80
--- http_config eval: $::HttpConfig
--- config
    location = /a {
        content_by_lua '
            local httpipe = require "resty.httpipe"
            local hp = httpipe:new()

            local scheme, _, port, _, _ = unpack(hp:parse_uri("http://www.upyun.com/foo"))
            ngx.say(scheme .. ":" .. tostring(port))
        ';
    }
--- request
GET /a
--- response_body
http:80
--- no_error_log
[error]
[warn]


=== TEST 2: http:443
--- http_config eval: $::HttpConfig
--- config
    location = /a {
        content_by_lua '
            local httpipe = require "resty.httpipe"
            local hp = httpipe:new()

            local function parse_uri(uri)
                local res, err = hp:parse_uri(uri)
                if res then
                    local scheme, _, port, _, _ = unpack(res)
                    ngx.say(scheme .. ":" .. tostring(port))
                end
                if err then
                    ngx.say(err)
                end
            end

            parse_uri("http://www.upyun.com/foo")
            parse_uri("https://www.upyun.com/foo")
            parse_uri("httpss://www.upyun.com/foo")
        ';
    }
--- request
GET /a
--- response_body
http:80
https:443
bad uri
--- no_error_log
[error]
[warn]
