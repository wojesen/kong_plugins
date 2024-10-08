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
local timestamp = require "kong.tools.timestamp"
local spanLayer = require("kong.plugins.skywalking.span_layer")
local SegmentRef = require("kong.plugins.skywalking.segment_ref")

local CONTEXT_CARRIER_KEY = 'sw8'

local _M = {}
-- local Span = {
--     span_id,
--     parent_span_id,
--     operation_name,
--     tags,
--     layer = spanLayer.NONE,
--     is_entry = false,
--     is_exit = false,
--     peer,
--     start_time,
--     end_time,
--     error_occurred = false,
--     component_id,
--     refs,
--     is_noop = false,
--     -- owner is a TracingContext reference
--     owner,
-- }

-- Due to nesting relationship inside Segment/Span/TracingContext at the runtime,
-- SpanProtocol is created to prepare JSON format serialization.
-- Following SkyWalking official trace protocol v3
-- https://github.com/apache/skywalking-data-collect-protocol/blob/master/language-agent/Tracing.proto
-- local SpanProtocol = {
--     spanId,
--     parentSpanId,
--     startTime,
--     endTime,
--     -- Array of RefProtocol
--     refs,
--     operationName,
--     peer,
--     spanType,
--     spanLayer,
--     componentId,
--     isError,
--     tags,
--     logs,
-- }

-- Create an entry span. Represent the HTTP incoming request.
-- @param contextCarrier, HTTP request header, which could carry the `sw8` context
function _M.createEntrySpan(operationName, context, parent, contextCarrier)
    local span = _M.new(operationName, context, parent)
    span.is_entry = true

    if contextCarrier ~= nil then
        local propagatedContext = contextCarrier[CONTEXT_CARRIER_KEY]
        if propagatedContext ~= nil then
            local ref = SegmentRef.fromSW8Value(propagatedContext)
            if ref ~= nil then
                -- If current trace id is generated by the context, in LUA case, mostly are yes
                -- use the ref trace id to override it, in order to keep trace id consistently same.
                context.internal.addRefIfFirst(context.internal, ref)
                span.refs[#span.refs + 1] = ref
            end
        end
    end

    return span
end

-- Create an exit span. Represent the HTTP outgoing request.
function _M.createExitSpan(operationName, context, parent, peer, contextCarrier)
    local span = _M.new(operationName, context, parent)
    span.is_exit = true
    span.peer = peer
    --print_r({"hhhhhhhhhhh"})
    --print_r(contextCarrier)
    --print_r({"jjjjjjjjjjjj"})
    if contextCarrier ~= nil then
        -- if there is contextCarrier container, the Span will inject the value based on the current tracing context
        local injectableRef = SegmentRef.new()
        injectableRef.trace_id = context.trace_id
        injectableRef.segment_id = context.segment_id
        injectableRef.span_id = span.span_id
        injectableRef.address_used_at_client = peer
        injectableRef.parent_service = context.service
        injectableRef.parent_service_instance = context.service_instance

        local firstSpan = context.internal.first_span
        local parentEndpointName
        parentEndpointName = firstSpan.operation_name
        injectableRef.parent_endpoint = parentEndpointName

        contextCarrier[CONTEXT_CARRIER_KEY] = SegmentRef.serialize(injectableRef)
    end

    return span
end

-- Create an local span. Local span is usually not used.
-- Typically, only one entry span and one exit span in the Nginx tracing segment.
function _M.createLocalSpan(operationName, context, parent)
    local span = _M.new(operationName, context, parent)
    return span
end

-- Create a default span.
-- Usually, this method wouldn't be called by outside directly.
-- Read newEntrySpan, newExitSpan and newLocalSpan for more details
function _M.new(operationName, context, parent)
    local span = _M.newNoOP()
    span.is_noop = false

    span.operation_name = operationName
    span.span_id = context.internal.nextSpanID(context.internal)

    if parent == nil then
        -- As the root span, the parent span id is -1
        span.parent_span_id = -1
    else
        span.parent_span_id = parent.span_id
    end

    context.internal.addActive(context.internal, span)
    span.refs = {}
    span.owner = context

    return span
end

function _M.newNoOP()
    return {
        layer = spanLayer.NONE,
        is_entry = false,
        is_exit = false,
        error_occurred = false,
        is_noop = true
    }
end

---- All belowing are instance methods

-- Set start time explicitly
function _M.start(span, startTime)
    if span.is_noop then
        return span
    end

    span.start_time = startTime

    return span
end

function _M.finishWithDuration(span, duration)
    if span.is_noop then
        return span
    end

    _M.finish(span, span.start_time + duration)

    return span
end

-- @param endTime, optional.
function _M.finish(span, endTime)
    if span.is_noop then
        return span
    end

    if endTime == nil then
        span.end_time = timestamp.get_utc()
    else
        span.end_time = endTime
    end
    span.owner.internal.finishSpan(span.owner.internal, span)

    return span
end

function _M.setComponentId(span, componentId)
    if span.is_noop then
        return span
    end
    span.component_id = componentId

    return span
end

function _M.setLayer(span, span_layer)
    if span.is_noop then
        return span
    end
    span.layer = span_layer

    return span
end

function _M.errorOccurred(span)
    if span.is_noop then
        return span
    end
    span.error_occurred = true

    return span
end

function _M.tag(span, tagKey, tagValue)
    if span.is_noop then
        return span
    end

    if span.tags == nil then
        span.tags = {}
    end

    local tag = {key = tagKey, value = tagValue}
    span.tags[#span.tags + 1] = tag

    return span
end

-- @param keyValuePairs, keyValuePairs is a typical {key=value, key1=value1}
function _M.log(span, timestamp, keyValuePairs)
    if span.is_noop then
        return span
    end

    if span.logs == nil then
        span.logs = {}
    end

    local logEntity = {time = timestamp, data = keyValuePairs}
    span.logs[#span.logs + 1] = logEntity

    return span
end

-- Return SpanProtocol
function _M.transform(span)
    local spanBuilder = {}
    spanBuilder.spanId = span.span_id
    spanBuilder.parentSpanId = span.parent_span_id
    spanBuilder.startTime = span.start_time
    spanBuilder.endTime = span.end_time
    -- Array of RefProtocol
    if #span.refs > 0 then
        spanBuilder.refs = {}
        for i, ref in ipairs(span.refs)
        do
            spanBuilder.refs[#spanBuilder.refs + 1] = SegmentRef.transform(ref)
        end
    end

    spanBuilder.operationName = span.operation_name
    spanBuilder.peer = span.peer
    if span.is_entry then
        spanBuilder.spanType = 'Entry'
    elseif span.is_exit then
        spanBuilder.spanType = 'Exit'
    else
        spanBuilder.spanType = 'Local'
    end
    if span.layer ~= spanLayer.NONE then
        spanBuilder.spanLayer = span.layer.name
    end
    spanBuilder.componentId = span.component_id
    spanBuilder.isError = span.error_occurred

    spanBuilder.tags = span.tags
    spanBuilder.logs = span.logs

    return spanBuilder
end

return _M
