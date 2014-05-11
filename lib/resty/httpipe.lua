-- Copyright (C) 2014 Monkey Zhang (timebug)


local type = type
local error = error
local pairs = pairs
local ipairs = ipairs
local rawset = rawset
local rawget = rawget
local sub = string.sub
local gsub = string.gsub
local tostring = tostring
local tonumber = tonumber
local tcp = ngx.socket.tcp
local match = string.match
local upper = string.upper
local lower = string.lower
local concat = table.concat
local insert = table.insert
local setmetatable = setmetatable
local escape_uri = ngx.escape_uri
local encode_args = ngx.encode_args
-- local print = print


local _M = { _VERSION = "0.04" }

--------------------------------------
-- LOCAL CONSTANTS                  --
--------------------------------------

local mt = { __index = _M }

local HTTP_1_1 = " HTTP/1.1\r\n"
local HTTP_1_0 = " HTTP/1.0\r\n"

local USER_AGENT = "Resty/HTTPipe-" .. _M._VERSION

local STATE_NOT_READY = 0
local STATE_BEGIN = 1
local STATE_READING_HEADER = 2
local STATE_READING_BODY = 3
local STATE_EOF = 4

local common_headers = {
    "Cache-Control",
    "Content-Length",
    "Content-Type",
    "Date",
    "ETag",
    "Expires",
    "Host",
    "Location",
    "User-Agent"
}

for _, key in ipairs(common_headers) do
    rawset(common_headers, key, key)
    rawset(common_headers, lower(key), key)
end

local state_handlers

--------------------------------------
-- HTTP BASE FUNCTIONS              --
--------------------------------------

local function normalize_header(key)
    local val = common_headers[key]
    if val then
        return val
    end
    key = lower(key)
    val = common_headers[lower(key)]
    if val then
        return val
    end

    key = gsub(key, "^%l", upper)
    key = gsub(key, "-%l", upper)
    return key
end


local function escape_path(path)
    local unescaped = {}
    local escaped_path = "/"

    gsub(path, "([^/]+)", function (s) insert(unescaped, s) end)

    local n = #unescaped
    for i=1, n - 1 do
        escaped_path = escaped_path .. escape_uri(unescaped[i]) .. "/"
    end

    if n > 0 then
        escaped_path = escaped_path .. escape_uri(unescaped[n])

        if sub(path, -1, -1) == "/" then
            escaped_path = escaped_path .. "/"
        end
    end

    return escaped_path
end


local function req_header(self, opts)
    local req = {
        upper(opts.method or "GET"),
        " "
    }

    self.method = upper(opts.method)

    local path = opts.path
    if type(path) ~= "string" then
        path = "/"
    elseif sub(path, 1, 1) ~= "/" then
        path = "/" .. path
    end
    insert(req, escape_path(path))

    if type(opts.query) == "table" then
        opts.query = encode_args(opts.query)
    end

    if type(opts.query) == "string" then
        insert(req, "?" .. opts.query)
    end

    if opts.version == 1 then
        insert(req, HTTP_1_1)
    else
        insert(req, HTTP_1_0)
    end

    opts.headers = opts.headers or {}
    local headers = {}
    for k, v in pairs(opts.headers) do
        headers[normalize_header(k)] = v
    end

    if opts.body then
        headers['Content-Length'] = #opts.body
    end

    if not headers['Host'] then
        headers['Host'] = opts.host
    end

    if not headers['User-Agent'] then
        headers['User-Agent'] = USER_AGENT
    end

    if not headers['Accept'] then
        headers['Accept'] = "*/*"
    end

    if opts.version == 0 and not headers['Connection'] then
        headers['Connection'] = "Keep-Alive"
    end

    for key, values in pairs(headers) do
        if type(values) ~= "table" then
            values = { values }
        end

        key = tostring(key)
        for _, value in pairs(values) do
            insert(req, key .. ": " .. tostring(value) .. "\r\n")
        end
    end

    insert(req, "\r\n")

    return concat(req)
end


--------------------------------------
-- HTTP PIPE FUNCTIONS              --
--------------------------------------

-- local hp, err = _M:new(sock?, chunk_size?)
function _M.new(self, sock, chunk_size)
    local state = STATE_NOT_READY

    if sock then
        state = STATE_BEGIN
    else
        local s, err = tcp()
        if not s then
            return nil, err
        end
        sock = s
    end

    return setmetatable({
        sock = sock,
        size = chunk_size or 8192,
        state = state,
        read_line = nil,
        read_timeout = nil,
        datalen = 0,
        chunked = false,
        keepalive = true,
        method = nil,
        eof = nil,
    }, mt)
end


-- local ok, err = _M:request(host, port, opts?)
function _M.request(self, host, port, opts)
    local sock = self.sock
    if not sock then
        return nil, "not initialized"
    end

    opts = opts or {}

    sock:settimeout(opts.timeout or 5000)

    local rc, err = sock:connect(host, port)
    if not rc then
        return nil, err
    end

    if opts.send_timeout then
        sock:settimeout(opts.send_timeout)
    end

    if opts.read_timeout then
        self.read_timeout = opts.read_timeout
    end

    local version = opts.version
    if version then
        if version ~= 0 and version ~= 1 then
            return nil, "unknow HTTP version"
        end
    else
        opts.version = 1
    end

    opts.host = host

    local header = req_header(self, opts)
    -- print(header)
    local bytes, err = sock:send(header)
    if not bytes then
        return nil, err
    end

    if opts and type(opts.body) == "string" then
        local bytes, err = sock:send(opts.body)
        if not bytes then
            return nil, err
        end
    end

    self.state = STATE_BEGIN

    return 1
end


-- local ok, err = _M:set_timeout(time)
function _M.set_timeout(self, time)
    local sock = self.sock
    if not sock then
        return nil, "not initialized"
    end

    sock:settimeout(time)

    return 1
end


local function discard_line(self)
    local read_line = self.read_line

    local line, err = read_line()
    if not line then
        return nil, nil, err
    end

    return 1
end


local function read_body(self)
    if self.method == "HEAD" then
        self.state = STATE_EOF
        return 'body_end', nil
    end

    local sock = self.sock
    local datalen = self.datalen
    local size = self.size

    if self.chunked == true and datalen == 0 then
        local read_line = self.read_line
        local data, err = read_line()

        if err then
            return nil, nil, err
        end

        if data == "" then
            data, err = read_line()
            if err then
                return nil, nil, err
            end
        end

        if data then
            if data == "0" then
                local ok, err = discard_line(self)
                if not ok then
                    return nil, nil, err
                end

                self.state = STATE_EOF
                return 'body_end', nil
            else
                local length = tonumber(data, 16)
                datalen = length
            end
        end
    end

    if datalen == 0 then
        self.state = STATE_EOF
        return 'body_end', nil
    end

    if datalen < size then
        size = datalen
    end

    local chunk, err, partial = sock:receive(size)

    local data = ""
    if not err then
        if chunk then
            data = chunk
        end
    elseif err == "closed" then
        self.state = STATE_EOF
        if partial then
            self.datalen = datalen - #partial
            if self.datalen ~= 0 then
                return nil, nil, err
            end
            return 'body', partial
        else
            return 'body_end', nil
        end
    else
        return nil, nil, err
    end

    self.datalen = datalen - size

    return 'body', data
end


local function read_header(self)
    local read_line = self.read_line

    local line, err = read_line()
    if not line then
        return nil, nil, err
    end

    if line == "" then
        self.state = STATE_READING_BODY
        return 'header_end', nil
    end

    local name, value = match(line, "^(.-):%s*(.*)")
    if not name then
        return 'header', line
    end

    local vname = lower(name)
    if vname == "content-length" then
        self.datalen = tonumber(value)
    end

    if vname == "transfer-encoding" and value ~= "identity" then
        self.chunked = true
    end

    if vname == "connection" and value == "close" then
        self.keepalive = false
    end

    return 'header', { normalize_header(name), value, line }
end


local function read_statusline(self)
    local sock = self.sock
    if self.read_line == nil then
        local rl, err = sock:receiveuntil("\r\n")
        if not rl then
            return nil, nil, err
        end
        self.read_line = rl
    end

    local read_line = self.read_line

    local line, err = read_line()
    if not line then
        return nil, nil, "read status line failed " .. err
    end

    local status = match(line, "HTTP/%d*%.%d* (%d%d%d)")
    if not status then
        -- return nil, nil, "not match statusline"
        return nil, nil, line
    end

    if status == "100" then
        local ok, err = discard_line(self)
        if not ok then
            return nil, nil, err
        end

        self.state = STATE_BEGIN
    else
        self.state = STATE_READING_HEADER
    end

    return 'statusline', status
end


-- local ok, err = _M:close(force?)
function _M.close(self, ...)
    local sock = self.sock
    if not sock then
        return nil, "not initialized"
    end

    self.eof = 1

    local force = ...
    if not force and self.keepalive then
        return sock:setkeepalive()
    end

    return sock:close()
end


local function eof(self)
    _M.close(self)
    return 'eof', nil
end

-- local typ, res, err = _M:read()
function _M.read(self)
    local sock = self.sock
    if not sock then
        return nil, nil, "not initialized"
    end

    if self.state == STATE_NOT_READY then
        return nil, nil, "not ready"
    end

    if self.read_timeout then
        sock:settimeout(self.read_timeout)
    end

    local handler = state_handlers[self.state]
    if handler then
        return handler(self)
    end

    return nil, nil, "bad state: " .. self.state
end

-- local bytes, err = _M:write(chunk)
function _M.write(self, chunk)
    local sock = self.sock
    if not sock then
        return nil, "not initialized"
    end

    return sock:send(chunk)
end


state_handlers = {
    read_statusline,
    read_header,
    read_body,
    eof
}


-- local res, err = _M:receive(callback?)
function _M.receive(self, ...)
    local sock = self.sock
    if not sock then
        return nil, "not initialized"
    end

    local callback = ...
    if type(callback) ~= "table" then
        callback = {}
    end

    local status
    local headers = {}
    local chunks = {}

    while not self.eof do
        local typ, res, err = _M.read(self)
        if not typ then
            return nil, err
        end

        if typ == 'statusline' then
            status = tonumber(res)
        end

        if typ == 'header' then
            if type(res) == "table" then
                headers[normalize_header(res[1])] = res[2]
            end
        end

        if typ == 'header_end' then
            if callback.header_filter then
                local rc = callback.header_filter(status, headers)
                if rc then break end
            end
        end

        if typ == 'body' then
            if callback.body_filter then
                local rc = callback.body_filter(res)
                if rc then break end
            else
                insert(chunks, res)
            end
        end

        if typ == 'eof' then
            break
        end
    end

    return { status = status, headers = headers, body = concat(chunks),
             eof = self.eof }
end


return _M
