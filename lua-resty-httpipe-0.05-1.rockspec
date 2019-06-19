package = "lua-resty-httpipe"
version = "0.05-1"
source = {
   url = "git://github.com/timebug/lua-resty-httpipe",
   tag = "v0.05",
}
description = {
   summary = "Lua HTTP client cosocket driver for OpenResty / ngx_lua, interfaces are more flexible",
   detailed = [[
        lua-resty-httpipe - Lua HTTP client cosocket driver for OpenResty / ngx_lua, interfaces are more flexible.
   ]],
   license = "2-clause BSD",
   homepage = "https://github.com/timebug/lua-resty-httpipe",
   maintainer = "Monkey Zhang <timebug.info@gmail.com>",
}
dependencies = {
   "lua >= 5.1"
}
build = {
   type = "builtin",
   modules = {
     ["resty.httpipe"] = "lib/resty/httpipe.lua",
   }
}
