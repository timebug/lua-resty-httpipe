# vim:set ft= ts=4 sw=4 et:

use Test::Nginx::Socket;
use Cwd qw(cwd);

plan tests => repeat_each() * (blocks() * 4);

my $pwd = cwd();

our $HttpConfig = qq{
    lua_package_path "$pwd/lib/?.lua;;";
};

$ENV{TEST_NGINX_RESOLVER} = '8.8.8.8';

no_long_string();
#no_diff();

run_tests();

__DATA__
=== TEST 1: Check eof status.
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua '
            local httpipe = require "resty.httpipe"
            local hp = httpipe:new()

            ngx.say(hp:eof())

            local res, err = hp:request("127.0.0.1", ngx.var.server_port, {
                path = "/b",
                stream = true,
            })

            ngx.say(hp:eof())

            repeat
                local chunk = res.body_reader()
                if chunk then
                   ngx.say(hp:eof())
                end
            until not chunk

            ngx.say(hp:eof())
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
GET /t
--- response_body
false
false
false
false
false
false
false
false
false
true
--- no_error_log
[error]
[warn]
