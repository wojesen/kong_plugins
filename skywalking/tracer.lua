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


local Span = require('kong.plugins.skywalking.span')
local kong = kong
local ngx = ngx

local Tracer = {}

function Tracer:start(config, correlation)
    local TC = require('kong.plugins.skywalking.tracing_context')
    local Layer = require('kong.plugins.skywalking.span_layer')
    local SegmentRef = require("kong.plugins.skywalking.segment_ref")

    local tracingContext
    local service_name = config.service_name
    local service_instance_name = config.service_instance_name
    tracingContext = TC.new(service_name, service_instance_name)

    -- Constant pre-defined in SkyWalking main repo
    -- 6000 represents Nginx
    local nginxComponentId = 6000

    local contextCarrier = {}
    contextCarrier["sw8"] = ngx.req.get_headers()["sw8"]
    contextCarrier["sw8-correlation"] = ngx.req.get_headers()["sw8-correlation"]
    local entrySpan = TC.createEntrySpan(tracingContext, ngx.var.uri, nil, contextCarrier)
    Span.start(entrySpan, ngx.now() * 1000)
    Span.setComponentId(entrySpan, nginxComponentId)
    Span.setLayer(entrySpan, Layer.HTTP)

    Span.tag(entrySpan, 'paas.clusterid', config.cluster_id)
    Span.tag(entrySpan, 'paas.tenant', config.tenant)
    Span.tag(entrySpan, 'paas.namespace', config.namespace)
    Span.tag(entrySpan, 'paas.version', config.version)
    Span.tag(entrySpan, 'paas.api_tenant', config.api_tenant)
    Span.tag(entrySpan, 'paas.api_namespace', config.api_namespace)
    Span.tag(entrySpan, 'paas.env_id', config.env_id)
    Span.tag(entrySpan, 'paas.env_name', config.env_name)


    local route = kong.router.get_route()
    if route and route.paths and #route.paths > 0 then
        Span.tag(entrySpan, 'route.path', route.paths[1])
    end
    Span.tag(entrySpan, 'http.method', kong.request.get_method())
    Span.tag(entrySpan, 'http.params', kong.request.get_scheme() .. '://' .. kong.request.get_host() .. ':' .. kong.request.get_port() .. kong.request.get_path_with_query())

    contextCarrier = {}
    -- Use the same URI to represent incoming and forwarding requests
    -- Change it if you need.
    local upstreamUri = ngx.var.uri

    --local upstreamServerName = kong.request.get_host()
    local ctx = ngx.ctx
    local upstreamServerName = ctx.balancer_data.host
    ------------------------------------------------------
    local exitSpan = TC.createExitSpan(tracingContext, upstreamUri, entrySpan, upstreamServerName, contextCarrier, correlation)
    Span.start(exitSpan, ngx.now() * 1000)
    Span.setComponentId(exitSpan, nginxComponentId)
    Span.setLayer(exitSpan, Layer.HTTP)

    for name, value in pairs(contextCarrier) do
        --print_r({"mmmmmmmmmmmmm"})
        --print_r({name})
        --print_r({SegmentRef.fromSW8Value(value)})
        --print_r({"nnnnnnnnnnnnnn"})
        ngx.req.set_header(name, value)
    end

    --local ctx = ngx.ctx
    --print_r({"bbbbbbbbb"})
    --print_r({ctx.balancer_data.host})
    --print_r({"hhhhhhhhhhhhhhhhhhh"})

    -- Push the data in the context
    kong.ctx.plugin.tracingContext = tracingContext
    kong.ctx.plugin.entrySpan = entrySpan
    kong.ctx.plugin.exitSpan = exitSpan

    local set_header = kong.response.set_header
    set_header("X-Kong-Proxy-TraceId", tracingContext.trace_id)
end

function Tracer:finish()
    -- Finish the exit span when received the first response package from upstream
    if kong.ctx.plugin.exitSpan ~= nil then
        Span.finish(kong.ctx.plugin.exitSpan, ngx.now() * 1000)
        --kong.ctx.plugin.exitSpan = nil
    end
end

function Tracer:prepareForReport()
    local TC = require('kong.plugins.skywalking.tracing_context')
    local Segment = require('kong.plugins.skywalking.segment')
    if kong.ctx.plugin.entrySpan ~= nil then
        Span.finish(kong.ctx.plugin.entrySpan, ngx.now() * 1000)
        local status, segment = TC.drainAfterFinished(kong.ctx.plugin.tracingContext)
        if status then
            local segmentJson = require('cjson').encode(Segment.transform(segment))
            --print_r({"ttttttttttt"})
            --print_r({segmentJson})
            --print_r({"ggggggggggg"})
            ngx.log(ngx.DEBUG, 'segment = ', segmentJson)

            local queue = ngx.shared.kong_db_cache
            local length = queue:lpush('sw_queue_segment', segmentJson)
            ngx.log(ngx.DEBUG, 'segment buffer size = ', queue:llen('sw_queue_segment'))
        end
    end
end

function Tracer:addUpstreamIp(ip)
    if kong.ctx.plugin.entrySpan ~= nil then
        Span.tag(kong.ctx.plugin.entrySpan, 'upstreamIp', ip)
    end
    if kong.ctx.plugin.exitSpan ~= nil then
        Span.tag(kong.ctx.plugin.exitSpan, 'upstreamIp', ip)
    end
end

function Tracer:addUpstreamHost()
    local ctx = ngx.ctx
    if kong.ctx.plugin.entrySpan ~= nil then
        if ctx and ctx.balancer_data and ctx.balancer_data.host then
            --print_r({"jjjjjjj"})
            --print_r({ctx.balancer_data.host})
            --print_r({"lllllllllllll"})
            Span.tag(kong.ctx.plugin.entrySpan, 'upstreamHost', ctx.balancer_data.host)
        end
    end
    if kong.ctx.plugin.exitSpan ~= nil then
        if ctx and ctx.balancer_data and ctx.balancer_data.host then
            Span.tag(kong.ctx.plugin.exitSpan, 'upstreamHost', ctx.balancer_data.host)
            kong.ctx.plugin.exitSpan.peer = ctx.balancer_data.host
        end
    end
end

return Tracer
