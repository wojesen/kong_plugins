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

local basic_serializer = require "kong.plugins.log-serializers.basic"
local body_transformer = require "kong.plugins.response-transformer.body_transformer"
local is_json_body = body_transformer.is_json_body
local ngx = ngx
local concat = table.concat
local lower = string.lower
local cjson = require "cjson"
local prometheus = require "kong.plugins.prometheus.exporter"
local kong = kong
local utils = require("kong.tools.utils")
local inflate_gzip = utils.inflate_gzip
local split = require "kong.tools.utils".split
local find = string.find
local table_clear = require "table.clear"
local url = require "socket.url"
local http = require "resty.http"
local fmt = string.format
local timer_at = ngx.timer.at
local headers_cache = {}
local params_cache = {
  ssl_verify = false,
  headers = headers_cache,
}
local parsed_urls_cache = {}
local kong_service_request_get_header = kong.request.get_header

local get_raw_body = kong.request.get_raw_body

local function parse_json(body)
  if body then
    local status, res = pcall(cjson.decode, body)
    if status then
      return res
    end
  end
end

local function parse_url(host_url)
  local parsed_url = parsed_urls_cache[host_url]

  if parsed_url then
    return parsed_url
  end

  parsed_url = url.parse(host_url)
  if not parsed_url.port then
    if parsed_url.scheme == "http" then
      parsed_url.port = 80
    elseif parsed_url.scheme == "https" then
      parsed_url.port = 443
    end
  end
  if not parsed_url.path then
    parsed_url.path = "/"
  end

  parsed_urls_cache[host_url] = parsed_url

  return parsed_url
end
local function parse_json(body)
  if body then
    local status, res = pcall(cjson.decode, body)
    if status then
      return res
    end
  end
end

local function calculate_token(conf)
  local method = conf.method
  local timeout = conf.timeout
  local keepalive = conf.keepalive
  local content_type = conf.content_type
  local http_endpoint = conf.http_endpoint
  local parsed_url = parse_url(http_endpoint)
  local host = parsed_url.host
  local port = tonumber(parsed_url.port)

  local httpc = http.new()
  httpc:set_timeout(timeout)

  table_clear(headers_cache)
  if conf.headers then
    for h, v in pairs(conf.headers) do
      headers_cache[h] = v
    end
  end

  headers_cache["Host"] = parsed_url.host
  headers_cache["Content-Type"] = content_type
  --headers_cache["Content-Length"] = #payload

  params_cache.method = method
  --params_cache.body = payload
  params_cache.keepalive_timeout = keepalive

  local url = fmt("%s://%s:%d%s", parsed_url.scheme, parsed_url.host, parsed_url.port, parsed_url.path)

  -- note: `httpc:request` makes a deep copy of `params_cache`, so it will be
  -- fine to reuse the table here
  local res, err = httpc:request_uri(url, params_cache)
  print_r({"qqqqqqqqqqqqqqqqqqqqqqqqqqq"})
  print_r({res})
  print_r({"wwwwwwwwwwwwwwwwwwwwwwwwwww"})
  if not res then
    return nil
  end
  -- always read response body, even if we discard it without using it on success
  local response_body = res.body
  local success = res.status < 400
  local err_msg

  if not success then
    return nil
  end
  return response_body
end

local function metrics(premature,conf,message)
  local serialized = {}
  if conf.per_consumer and message.consumer ~= nil then
    serialized.consumer = message.consumer.username
  end
  local total_tokens = ngx.ctx.total_tokens
  local prompt_tokens = ngx.ctx.prompt_tokens
  local completion_tokens = ngx.ctx.completion_tokens
  local envId = ngx.ctx.envId
  local envName = ngx.ctx.envName
  local groupId = ngx.ctx.groupId
  local groupName = ngx.ctx.groupName
  local apiId = ngx.ctx.apiId
  local apiName = ngx.ctx.apiName
  local namespace = ngx.ctx.namespace
  local userAgent = ngx.ctx.userAgent
  local remoteAddr = ngx.ctx.remoteAddr
  if total_tokens and total_tokens>0 then
    serialized.total_tokens = total_tokens
  end
  if prompt_tokens and prompt_tokens>0 then
    serialized.prompt_tokens = prompt_tokens
  end
  if completion_tokens and completion_tokens>0 then
    serialized.completion_tokens = completion_tokens
  end
  if total_tokens and prompt_tokens and completion_tokens then
    serialized.total_tokens = total_tokens
    serialized.prompt_tokens = prompt_tokens
    serialized.completion_tokens = completion_tokens
  else
    local response_body = calculate_token(conf)
    if response_body then
      local parameters = parse_json(response_body)
      print_r({"xxxxxxxxxxxxxxxx"})
      print_r({parameters})
      print_r({"ccccccccccccccccccccccccc"})
      print_r({parameters["prompt_tokens"]})
      print_r({"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"})
      if parameters and type(parameters) =="table" and parameters["prompt_tokens"] ~=nil then
        serialized.prompt_tokens = parameters["prompt_tokens"]
      end
      if parameters and type(parameters) =="table" and parameters["completion_tokens"] ~=nil then
        serialized.completion_tokens = parameters["completion_tokens"]
      end
      if parameters and type(parameters) =="table" and parameters["total_tokens"] ~=nil then
        serialized.total_tokens = parameters["total_tokens"]
      end
    end
  end
  local headers = ngx.resp.get_headers()
  if headers and headers["x-request-model"] then
    serialized.model = headers["x-request-model"]
  end
  if envId  then
    serialized.envId = envId
  end
  if envName then
    serialized.envName = envName
  end
  if groupId then
    serialized.groupId = groupId
  end
  if groupName then
    serialized.groupName = groupName
  end
  if apiId then
    serialized.apiId = apiId
  end
  if apiName then
    serialized.apiName = apiName
  end
  if namespace then
    serialized.namespace = namespace
  end
  if userAgent then
    serialized.userAgent = userAgent
  end
  if remoteAddr then
    serialized.remoteAddr = remoteAddr
  end
  prometheus.log(message, serialized)
end

local function is_stream_body(content_type)
return content_type and find(lower(content_type), "text/event-stream", nil, true)
end


local function TableToStr(t)
  if t == nil then return "" end
  local retstr= "{"

  local i = 1
  for key,value in pairs(t) do
    local signal = ","
    if i==1 then
      signal = ""
    end

    if key == i then
      retstr = retstr..signal..ToStringEx(value)
    else
      if type(key)=='number' or type(key) == 'string' then
        retstr = retstr..signal..'['..ToStringEx(key).."]="..ToStringEx(value)
      else
        if type(key)=='userdata' then
          retstr = retstr..signal.."*s"..TableToStr(getmetatable(key)).."*e".."="..ToStringEx(value)
        else
          retstr = retstr..signal..key.."="..ToStringEx(value)
        end
      end
    end

    i = i+1
  end

  retstr = retstr.."}"
  return retstr
end
local function get_user_agent()
  local user_agent = kong.request.get_headers()["user-agent"]
  if user_agent== nil then
    return ""
  end
  if type(user_agent) == "table" then
    return TableToStr(user_agent)
  end
  return user_agent
end

prometheus.init()


local PrometheusHandler = {
  PRIORITY = 13,
  VERSION  = "1.6.0",
}

function PrometheusHandler.init_worker()
  prometheus.init_worker()
end

function PrometheusHandler:access(conf)
  local user_agent = get_user_agent()
  ngx.ctx.userAgent = user_agent
  local remoteAddr = kong.client.get_forwarded_ip()
  ngx.ctx.remoteAddr = remoteAddr
end

function PrometheusHandler.log(self, conf)
  local message = kong.log.serialize()
  timer_at(0, metrics, conf,message)
end

--function PrometheusHandler:body_filter(conf)
--  local ai_api_go = ngx.ctx.ai_api_go
--  --非AI得服务不需要处理报文
--  if ai_api_go == nil then
--    --print_r({"heiheihei"})
--    return
--  end
--  local isLimit =kong.response.get_header("TokenLimit-Limit-Exe")
--  if isLimit then
--    return
--  end
--  local total_tokens = ngx.ctx.total_tokens
--  local prompt_tokens = ngx.ctx.prompt_tokens
--  local completion_tokens = ngx.ctx.completion_tokens
--  if total_tokens and prompt_tokens and completion_tokens then
--    return
--  end
--
--  local ctx = ngx.ctx
--  local chunk, eof = ngx.arg[1], ngx.arg[2]
--  ctx.rt_body_chunks = ctx.rt_body_chunks or {}
--  ctx.rt_body_chunk_number = ctx.rt_body_chunk_number or 1
--  if eof then
--    local status = kong.response.get_status()
--    if status ~= 200 then
--      return
--    end
--    local chunks = concat(ctx.rt_body_chunks)
--    if is_stream_body(kong.response.get_header("Content-Type")) then
--      local items = split(chunks, "data: ")
--      local content = ""
--      for i = 1, #items do
--        --print_r({items[i]})
--        if items[i] and items[i] ~= "" then
--          local parameters = parse_json(items[i])
--          if parameters and type(parameters) =="table" and parameters["choices"] ~=nil and type(parameters["choices"]) == "table" then
--            for j = 1, #parameters["choices"] do
--              if parameters["choices"][j] and type(parameters["choices"][j]) == "table" and parameters["choices"][j]["delta"] and type(parameters["choices"][j]["delta"]) == "table" and parameters["choices"][j]["delta"]["content"]  then
--                content = content .. tostring(parameters["choices"][j]["delta"]["content"])
--              end
--            end
--          end
--        end
--      end
--      local prompt_tokens = 0
--      if ngx.ctx.prompt_tokens_go then
--        prompt_tokens = ngx.ctx.prompt_tokens_go
--      end
--      ngx.ctx.prompt_tokens = prompt_tokens
--      local completion_tokens = 0
--      if content and content ~= "" then
--        completion_tokens = string.len(content)
--      end
--      ngx.ctx.completion_tokens = completion_tokens
--      ngx.ctx.total_tokens =completion_tokens + prompt_tokens
--    elseif is_json_body(kong.response.get_header("Content-Type")) then
--      local encode = kong.response.get_header("content-encoding")
--      local json_body
--      if encode and encode == "gzip" then
--        local inflateGzip = inflate_gzip(chunks)
--        json_body = parse_json(inflateGzip)
--      else
--        json_body = parse_json(chunks)
--      end
--      if json_body and type(json_body) =="table" and type(json_body["usage"]) =="table" and json_body["usage"] ~= nil and type(json_body["usage"]["total_tokens"]) ~="table" and json_body["usage"]["total_tokens"] ~=nil and type(json_body["usage"]["prompt_tokens"]) ~="table"  and json_body["usage"]["prompt_tokens"] ~=nil and type(json_body["usage"]["completion_tokens"]) ~="table"  and json_body["usage"]["completion_tokens"] ~=nil then
--        ngx.ctx.total_tokens =json_body["usage"]["total_tokens"]
--        ngx.ctx.prompt_tokens = json_body["usage"]["prompt_tokens"]
--        ngx.ctx.completion_tokens = json_body["usage"]["completion_tokens"]
--      end
--      if json_body and type(json_body) =="table" and type(json_body["usage"]) =="table" and json_body["usage"] ~= nil and type(json_body["usage"]["total_tokens"]) ~="table" and json_body["usage"]["total_tokens"] ~=nil and type(json_body["usage"]["input_tokens"]) ~="table"  and json_body["usage"]["input_tokens"] ~=nil and type(json_body["usage"]["output_tokens"]) ~="table"  and json_body["usage"]["output_tokens"] ~=nil then
--        ngx.ctx.total_tokens =json_body["usage"]["total_tokens"]
--        ngx.ctx.prompt_tokens = json_body["usage"]["input_tokens"]
--        ngx.ctx.completion_tokens = json_body["usage"]["output_tokens"]
--      end
--    end
--    ngx.arg[1] = chunks
--  else
--    ctx.rt_body_chunks[ctx.rt_body_chunk_number] = chunk
--    ctx.rt_body_chunk_number = ctx.rt_body_chunk_number + 1
--    ngx.arg[1] = nil
--  end
--end


return PrometheusHandler
