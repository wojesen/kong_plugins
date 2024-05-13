-- Copyright (c) Kong Inc. 2020
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





local ngx = ngx
local kong = kong


local ngx_arg = ngx.arg

local kong_request_get_path = kong.request.get_path
local kong_request_get_method = kong.request.get_method
local kong_request_get_raw_body = kong.request.get_raw_body
local kong_response_exit = kong.response.exit
local kong_response_set_header = kong.response.set_header
local kong_service_request_set_header = kong.service.request.set_header
local kong_service_request_set_method = kong.service.request.set_method
local kong_service_request_set_raw_body = kong.service.request.set_raw_body

--local core        = require("kong.plugins.grpc-gateway2")
local proto       = require("kong.plugins.grpc-gateway2.proto")
local request     = require("kong.plugins.grpc-gateway2.request")
local response    = require("kong.plugins.grpc-gateway2.response")

local grpc_gateway2 = {
  PRIORITY = 998,
  VERSION = '0.2.0',
}


local CORS_HEADERS = {
  ["Content-Type"] = "application/json",
  ["Access-Control-Allow-Origin"] = "*",
  ["Access-Control-Allow-Methods"] = "GET,POST,PATCH,DELETE",
  ["Access-Control-Allow-Headers"] = "content-type", -- TODO: more headers?
}

function grpc_gateway2:access(conf)
  local api_ctx = {}
  ngx.ctx.api_ctx = api_ctx
  --local proto_id = conf.proto_id
  --if not proto_id then
  --  core.log.error("proto id miss: ", proto_id)
  --  return
  --end

  local proto_obj, err = proto.fetch("1",conf.content)
  if err then
    --core.log.error("proto load error: ", err)
    return
  end
  --local op_option ={"int64_as_string"}
  local op_option ={}
  local ok, err, err_code = request(proto_obj,  conf.service,
          conf.method, op_option, 0)
  if not ok then
    --core.log.error("transform request error: ", err)
    return err_code
  end

  api_ctx.proto_obj = proto_obj
  api_ctx._plugin_name = "grpc-gateway2"
end

local status_rel = {
  ["1"] = 499,    -- CANCELLED
  ["2"] = 500,    -- UNKNOWN
  ["3"] = 400,    -- INVALID_ARGUMENT
  ["4"] = 504,    -- DEADLINE_EXCEEDED
  ["5"] = 404,    -- NOT_FOUND
  ["6"] = 409,    -- ALREADY_EXISTS
  ["7"] = 403,    -- PERMISSION_DENIED
  ["8"] = 429,    -- RESOURCE_EXHAUSTED
  ["9"] = 400,    -- FAILED_PRECONDITION
  ["10"] = 409,   -- ABORTED
  ["11"] = 400,   -- OUT_OF_RANGE
  ["12"] = 501,   -- UNIMPLEMENTED
  ["13"] = 500,   -- INTERNAL
  ["14"] = 503,   -- UNAVAILABLE
  ["15"] = 500,   -- DATA_LOSS
  ["16"] = 401,   -- UNAUTHENTICATED
}
-- https://github.com/googleapis/googleapis/blob/master/google/rpc/code.proto
local grpc_status_map = {
   [0] = 200, -- OK
   [1] = 499, -- CANCELLED
   [2] = 500, -- UNKNOWN
   [3] = 400, -- INVALID_ARGUMENT
   [4] = 504, -- DEADLINE_EXCEEDED
   [5] = 404, -- NOT_FOUND
   [6] = 409, -- ALREADY_EXISTS
   [7] = 403, -- PERMISSION_DENIED
  [16] = 401, -- UNAUTHENTICATED
   [8] = 429, -- RESOURCE_EXHAUSTED
   [9] = 400, -- FAILED_PRECONDITION
  [10] = 409, -- ABORTED
  [11] = 400, -- OUT_OF_RANGE
  [12] = 500, -- UNIMPLEMENTED
  [13] = 500, -- INTERNAL
  [14] = 503, -- UNAVAILABLE
  [15] = 500, -- DATA_LOSS
}

function grpc_gateway2.init()
  proto.init()
end


function grpc_gateway2.destroy()
  proto.destroy()
end


function grpc_gateway2:header_filter(conf)
  if ngx.status >= 300 then
    return
  end

  ngx.header["Content-Type"] = "application/json"
  ngx.header.content_length = nil

  local headers = ngx.resp.get_headers()

  if headers["grpc-status"] ~= nil and headers["grpc-status"] ~= "0" then
    local http_status = status_rel[headers["grpc-status"]]
    if http_status ~= nil then
      ngx.status = http_status
    else
      ngx.status = 599
    end
  else
    -- The error response body does not contain grpc-status and grpc-message
    ngx.header["Trailer"] = {"grpc-status", "grpc-message"}
  end
end


function grpc_gateway2:body_filter(conf)
  local api_ctx = ngx.ctx.api_ctx
  if ngx.status >= 300 and not conf.show_status_in_body then
    return
  end

  local proto_obj = api_ctx.proto_obj
  if not proto_obj then
    return
  end
  local op_option ={}
  local err = response(api_ctx, proto_obj, conf.service,
          conf.method, op_option,
          false, "")
  if err then
    --core.log.error("transform response error: ", err)
    return
  end
end


return grpc_gateway2
