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
=== TEST 1: Simple get + redirect.
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
                allow_redirects = true
            })

            ngx.print(res.body)
        ';
    }
    location = /b {
        content_by_lua 'ngx.redirect("http://127.0.0.1:" .. tostring(ngx.var.server_port) .. "/c", 301)';
    }
    location = /c {
        echo "OK";
    }
--- request
GET /a
--- response_body
OK
--- no_error_log
[error]
[warn]
