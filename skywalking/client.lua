--
-- Licensed to the Apache Software Foundation (ASF) under one or more
-- contributor license agreements.  See the NOTICE file distributed with
-- this work for additional information regarding copyright ownership.
-- The ASF licenses this file to You under the Apache License, Version 2.0
-- (the "License"); you may not use this file except in compliance with
-- the License.  You may obtain a copy of the License at
--
--    http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.
--
local pl_stringx = require "pl.stringx"
local print = print
local tconcat = table.concat
local tinsert = table.insert
local srep = string.rep
local type = type
local pairs = pairs
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


local SEGMENT_BATCH_COUNT = 100

local Client = {}

local log = kong.log

-- Tracing timer reports instance properties report, keeps alive and sends traces
-- After report instance properties successfully, it sends keep alive packages.
function Client:startBackendTimer(config)
    local metadata_buffer = ngx.shared.kong_db_cache

    local service_name = config.service_name
    local service_instance_name = config.service_instance_name
    local heartbeat_timer = metadata_buffer:get('sw_heartbeat_timer')

    -- The codes of timer setup is following the OpenResty timer doc
    local delay = 3  -- in seconds
    local new_timer = ngx.timer.at
    local check

    check = function(premature)
        if not premature then
            local instancePropertiesSubmitted = metadata_buffer:get('sw_instancePropertiesSubmitted')
            if (instancePropertiesSubmitted == nil or instancePropertiesSubmitted == false) then
                self:reportServiceInstance(metadata_buffer, config)
            else
                self:ping(metadata_buffer, config)
            end

            self:reportTraces(metadata_buffer, config)

            -- do the health check
            local ok, err = new_timer(delay, check)
            if not ok then
                log.err("failed to create timer: ", err)
                return
            end
        end
    end

    local worker_id = config.worker_id
    --print_r({"dddddddddddd"})
    --print_r({ngx.worker.id()})
    --print_r({worker_id})
    --print_r({heartbeat_timer})
    --print_r({"fffffffffffff"})
    if worker_id == ngx.worker.id() and heartbeat_timer ~= true then
        local ok, err = new_timer(delay, check)
        if not ok then
            log.err("failed to create timer: ", err)
            return
        end
        metadata_buffer:set('sw_heartbeat_timer',true)

    end
end

function Client:reportServiceInstance(metadata_buffer, config)

    local service_name = config.service_name
    local service_instance_name = config.service_instance_name

    local cjson = require('cjson')
    local reportInstance = require("kong.plugins.skywalking.management").newReportInstanceProperties(service_name, service_instance_name)
    local reportInstanceParam, err = cjson.encode(reportInstance)
    if err then
        log.err("Request to report instance fails, ", err)
        return
    end

    local http = require('resty.http')
    local httpc = http.new()
    local uri = config.backend_http_uri .. '/v3/management/reportProperties'

    local res, err = httpc:request_uri(uri, {
        method = "POST",
        body = reportInstanceParam,
        headers = {
            ["Content-Type"] = "application/json",
        },
    })

    if not res then
        log.err("Instance report fails, uri:", uri, ", err:", err)
    elseif res.status == 200 then
        log.debug("Instance report, uri:", uri, ", response = ", res.body)
        metadata_buffer:set('sw_instancePropertiesSubmitted', true)
    else
        log.err("Instance report fails, uri:", uri, ", response code ", res.status)
    end
end

-- Ping the backend to update instance heartheat
function Client:ping(metadata_buffer, config)

    local service_name = config.service_name
    local service_instance_name = config.service_instance_name

    local cjson = require('cjson')
    local pingPkg = require("kong.plugins.skywalking.management").newServiceInstancePingPkg(service_name, service_instance_name)
    local pingPkgParam, err = cjson.encode(pingPkg)
    if err then
        log.err("Agent ping fails, ", err)
    end

    local http = require('resty.http')
    local httpc = http.new()
    local uri = config.backend_http_uri .. '/v3/management/keepAlive'

    local res, err = httpc:request_uri(uri, {
        method = "POST",
        body = pingPkgParam,
        headers = {
            ["Content-Type"] = "application/json",
        },
    })

    if err == nil then
        if res.status ~= 200 then
            log.err("Agent ping fails, uri:", uri, ", response code ", res.status)
        end
    else
        log.err("Agent ping fails, uri:", uri, ", ", err)
    end
end

-- Send segemnts data to backend
local function sendSegments(segmentTransform, backend_http_uri)
    --print_r({"eeeeeeeeeeee"})
    --print_r({segmentTransform})
    --print_r({"rrrrrrrrrrrrr"})
    local http = require('resty.http')
    local httpc = http.new()

    local uri = backend_http_uri .. '/v3/segments'
    local res, err = httpc:request_uri(uri, {
        method = "POST",
        body = segmentTransform,
        headers = {
            ["Content-Type"] = "application/json",
        },
    })

    if err == nil then
        if res.status ~= 200 then
            log.err("Segment report fails, uri:", uri, ", response code ", res.status)
            return false
        end
    else
        log.err("Segment report fails, uri:", uri, ", ", err)
        return false
    end

    return true
end

-- Report trace segments to the backend
function Client:reportTraces(metadata_buffer, config)

    local queue = ngx.shared.kong_db_cache
    local segment = queue:rpop('sw_queue_segment')
    local segmentTransform = ''

    local count = 0
    local totalCount = 0

    while segment ~= nil
    do
        if #segmentTransform > 0 then
            segmentTransform = segmentTransform .. ','
        end

        segmentTransform = segmentTransform .. segment
        segment = queue:rpop('sw_queue_segment')
        count = count + 1
        if count >= SEGMENT_BATCH_COUNT then
            if sendSegments('[' .. segmentTransform .. ']', config.backend_http_uri) then
                totalCount = totalCount + count
            end

            segmentTransform = ''
            count = 0
        end
    end

    if #segmentTransform > 0 then
        if sendSegments('[' .. segmentTransform .. ']', config.backend_http_uri) then
            totalCount = totalCount + count
        end
    end

    if totalCount > 0 then
        log.debug(totalCount,  " segments reported.")
    end
end

return Client
