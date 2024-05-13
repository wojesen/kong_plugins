local print = print
local tconcat = table.concat
local tinsert = table.insert
local srep = string.rep
local tostring = tostring
local next = next

function print_r(root)
    local cache = {  [root] = "." }
    local function _dump(t,space,name)
        local temp = {}
        for k,v in pairs(t) do
            local key = tostring(k)
            if cache[v] then
                tinsert(temp,"+" .. key .. " {" .. cache[v].."}")
            elseif type(v) == "table" then
                local new_key = name .. "." .. key
                cache[v] = new_key
                tinsert(temp,"+" .. key .. _dump(v,space .. (next(t,k) and "|" or " " ).. srep(" ",#key),new_key))
            else
                tinsert(temp,"+" .. key .. " [" .. tostring(v).."]")
            end
        end
        return tconcat(temp,"\n"..space)
    end
    print(_dump(root, "",""))
end

--
-- Licensed to the Apache Software Foundation (ASF) under one or more
-- contributor license agreements.  See the NOTICE file distributed with
-- this work for additional information regarding copyright ownership.
-- The ASF licenses this file to You under the Apache License, Version 2.0
-- (the "License"); you may not use this file except in compliance with
-- the License.  You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.
--

local util   = require("kong.plugins.grpc-gateway2.util")
--local core   = require("kong.plugins.grpc-gateway2")
local pb     = require("pb")
local bit    = require("bit")
local ngx    = ngx
local string = string
local table  = table
local pcall = pcall
local tonumber = tonumber
local req_read_body = ngx.req.read_body
local kong = kong
local kong_service_request_set_header = kong.service.request.set_header
return function (proto, service, method, pb_option, deadline, default_values)
    --core.log.info("proto: ", core.json.delay_encode(proto, true))
    local m = util.find_method(proto, service, method)
    if not m then
        return false, "Undefined service method: " .. service .. "/" .. method
                      .. " end", 503
    end

    req_read_body()

    local pb_old_state = pb.state(proto.pb_state)
    util.set_options(proto, pb_option)

    local map_message = util.map_message(m.input_type, default_values or {})
    local ok, encoded = pcall(pb.encode, m.input_type, map_message)
    pb.state(pb_old_state)

    if not ok or not encoded then
        return false, "failed to encode request data to protobuf", 400
    end

    local size = #encoded
    local prefix = {
        string.char(0),
        string.char(bit.band(bit.rshift(size, 24), 0xFF)),
        string.char(bit.band(bit.rshift(size, 16), 0xFF)),
        string.char(bit.band(bit.rshift(size, 8), 0xFF)),
        string.char(bit.band(size, 0xFF))
    }

    kong_service_request_set_header("Content-Type", "application/grpc")
    kong_service_request_set_header("TE", "trailers")

    local message = table.concat(prefix, "") .. encoded
    --message="hello"
    ngx.req.set_method(ngx.HTTP_POST)
    ngx.req.set_uri("/" .. service .. "/" .. method, false)
    ngx.req.set_uri_args({})
    ngx.req.set_body_data(message)

    local dl = tonumber(deadline)
    if dl~= nil and dl > 0 then
        ngx.req.set_header("grpc-timeout",  dl .. "m")
    end

    return true
end
