-- Copyright (C) Kong Inc.
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


local timestamp = require "kong.tools.timestamp"
local policies = require "kong.plugins.circuit-breaker.policies"


local kong = kong
local ngx = ngx
local max = math.max
local time = ngx.time
local floor = math.floor
local pairs = pairs
local error = error
local tostring = tostring
local timer_at = ngx.timer.at


local EMPTY = {}
local EXPIRATION = require "kong.plugins.circuit-breaker.expiration"


local LATENCY_RATELIMIT_LIMIT     = "Latency-RateLimit-Limit"
local LATENCY_RATELIMIT_REMAINING = "Latency-RateLimit-Remaining"
local LATENCY_RATELIMIT_RESET     = "Latency-RateLimit-Reset"
local RETRY_AFTER         = "Retry-After"


local X_LATENCY_RATELIMIT_LIMIT = {
  second = "X-Latency-RateLimit-Limit-Second",
  minute = "X-Latency-RateLimit-Limit-Minute",
  hour   = "X-Latency-RateLimit-Limit-Hour",
  day    = "X-Latency-RateLimit-Limit-Day",
  month  = "X-Latency-RateLimit-Limit-Month",
  year   = "X-Latency-RateLimit-Limit-Year",
}

local X_LATENCY_RATELIMIT_REMAINING = {
  second = "X-Latency-RateLimit-Remaining-Second",
  minute = "X-Latency-RateLimit-Remaining-Minute",
  hour   = "X-Latency-RateLimit-Remaining-Hour",
  day    = "X-Latency-RateLimit-Remaining-Day",
  month  = "X-Latency-RateLimit-Remaining-Month",
  year   = "X-Latency-RateLimit-Remaining-Year",
}


local CircuitBreakerHandler = {}


CircuitBreakerHandler.PRIORITY = 901
CircuitBreakerHandler.VERSION = "2.4.0"


local function get_identifier(conf)
  local identifier

  if conf.limit_by == "service" then
    identifier = (kong.router.get_service() or
                  EMPTY).id
  elseif conf.limit_by == "consumer" then
    identifier = (kong.client.get_consumer() or
                  kong.client.get_credential() or
                  EMPTY).id

  elseif conf.limit_by == "credential" then
    identifier = (kong.client.get_credential() or
                  EMPTY).id

  elseif conf.limit_by == "header" then
    identifier = kong.request.get_header(conf.header_name)

  elseif conf.limit_by == "path" then
    local req_path = kong.request.get_path()
    if req_path == conf.path then
      identifier = req_path
    end
  end

  return identifier or kong.client.get_forwarded_ip()
end


local function get_usage(conf, identifier, current_timestamp, limits)
  local usage = {}
  local stop
  for period, limit in pairs(limits) do
    local current_avg,count, err = policies[conf.policy].usage(conf, identifier, period, current_timestamp)
    if conf.ingnore ~=0 and count<conf.ingnore then
      return 0, false,nil
    end
    if err then
      return nil, nil, err
    end
    -- Recording usage
    usage[period] = {
      limit = limit,
      avg = current_avg,
    }
    --if conf.limit_type == "latency" then
    --  if current_avg >= limit then
    --    stop = period
    --  end
    --elseif conf.limit_type == "error" then
    --  local err = tonumber(current_avg*100)
    --  if err >= limit then
    --    stop = period
    --  end
    --end
    local err = tonumber(current_avg*100)
    if err >= limit then
      stop = period
    end
  end

  return usage, stop
end


local function increment(premature, conf, ...)
  if premature then
    return
  end

  policies[conf.policy].increment(conf, ...)
end


function CircuitBreakerHandler:access(conf)
  local current_timestamp = time() * 1000

  -- Consumer is identified by ip address or authenticated_credential id
  local identifier = get_identifier(conf)
  local fault_tolerant = conf.fault_tolerant

  -- Load current metric for configured period
  local limits = {
    second = conf.second,
    minute = conf.minute,
    hour = conf.hour,
    day = conf.day,
    month = conf.month,
    year = conf.year,
  }

  local usage, stop, err = get_usage(conf, identifier, current_timestamp, limits)
  if err then
    if not fault_tolerant then
      return error(err)
    end

    kong.log.err("failed to get usage: ", tostring(err))
  end

  if usage then
    -- Adding headers
    local reset
    local headers
    --if not conf.hide_client_headers then
    --  headers = {}
    --  local timestamps
    --  local limit
    --  local window
    --  local remaining
    --  for k, v in pairs(usage) do
    --    local current_limit = v.limit
    --    local current_window = EXPIRATION[k]
    --    local current_remaining = v.remaining
    --    if stop == nil or stop == k then
    --      current_remaining = current_remaining - 1
    --    end
    --    current_remaining = max(0, current_remaining)
    --
    --    if not limit or (current_remaining < remaining)
    --                 or (current_remaining == remaining and
    --                     current_window > window)
    --    then
    --      limit = current_limit
    --      window = current_window
    --      remaining = current_remaining
    --
    --      if not timestamps then
    --        timestamps = timestamp.get_timestamps(current_timestamp)
    --      end
    --
    --      reset = max(1, window - floor((current_timestamp - timestamps[k]) / 1000))
    --    end
    --
    --    headers[X_LATENCY_RATELIMIT_LIMIT[k]] = current_limit
    --    headers[X_LATENCY_RATELIMIT_REMAINING[k]] = current_remaining
    --  end
    --
    --  headers[LATENCY_RATELIMIT_LIMIT] = limit
    --  headers[LATENCY_RATELIMIT_REMAINING] = remaining
    --  headers[LATENCY_RATELIMIT_RESET] = reset
    --end

    -- If limit is exceeded, terminate the request
    if stop then
      ngx.ctx.latency_limit = true
      headers = headers or {}
      headers[RETRY_AFTER] = reset
      --return kong.response.error(429, "API latency limit exceeded", headers)
      local status  = conf.status_code
      local content = conf.body
      local req_headers, req_query
      if conf.echo then
        content = {
          message = conf.message or DEFAULT_RESPONSE[status],
          kong = {
            node_id = kong.node.get_id(),
            worker_pid = ngx.worker.pid(),
            hostname = kong.node.get_hostname(),
          },
          request = {
            scheme = kong.request.get_scheme(),
            host = kong.request.get_host(),
            port = kong.request.get_port(),
            headers = req_headers,
            query = req_query,
            body = kong.request.get_body(),
            raw_body = kong.request.get_raw_body(),
            method = kong.request.get_method(),
            path = kong.request.get_path(),
          },
          matched_route = kong.router.get_route(),
          matched_service = kong.router.get_service(),
        }

        return kong.response.exit(status, content)
      end

      if content then
        local headers = {
          ["Content-Type"] = conf.content_type
        }

        return kong.response.exit(status, content, headers)
      end

      local message = conf.message or DEFAULT_RESPONSE[status]
      return kong.response.exit(status, message and { message = message } or nil)
    end

    if headers then
      kong.response.set_headers(headers)
    end
  end

  --local ok, err = timer_at(0, increment, conf, limits, identifier, current_timestamp, 1)
  --if not ok then
  --  kong.log.err("failed to create timer: ", err)
  --end
end


function CircuitBreakerHandler:log(conf)
  local latency_limit = ngx.ctx.latency_limit
  if latency_limit then
    return
  end
  local ongx = (options or {}).ngx or ngx
  local status = ongx.status
  local current_timestamp = time() * 1000
  local identifier = get_identifier(conf)
  -- Load current metric for configured period
  local limits = {
    second = conf.second,
    minute = conf.minute,
    hour = conf.hour,
    day = conf.day,
    month = conf.month,
    year = conf.year,
  }
  local http_request_time = tonumber(ngx.now() - ngx.req.start_time()) * 1000
  if conf.limit_type =="latency" then
    --print_r({"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"})
    --print_r({http_request_time})
    --print_r({"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"})
    if conf.latency_threshold>0  then
      if http_request_time>conf.latency_threshold then
        local ok, err = timer_at(0, increment, conf, limits, identifier, current_timestamp, 1)
      else
        local ok, err = timer_at(0, increment, conf, limits, identifier, current_timestamp, 0)
      end
    else
      local ok, err = timer_at(0, increment, conf, limits, identifier, current_timestamp, 1)
    end
    if not ok then
      kong.log.err("failed to create timer: ", err)
    end
  elseif conf.limit_type =="error" then
    if  tonumber(status)>400 and tonumber(status)<600 then
      local ok, err = timer_at(0, increment, conf, limits, identifier, current_timestamp, 1)
      if not ok then
        kong.log.err("failed to create timer: ", err)
      end
    else
      local ok, err = timer_at(0, increment, conf, limits, identifier, current_timestamp, 0)
      if not ok then
        kong.log.err("failed to create timer: ", err)
      end
    end
  end
  --local api_identifier = helpers.get_api_identifier()
  --local cb = kong.ctx.plugin.cb
  --
  --if cb == nil then
  --  return
  --end
  --if cb._last_state_notified == false then
  --  cb._last_state_notified = true
  --  -- Prepare latest state change and set it in context.
  --  -- This data can be used later to do logging in a different plugin.
  --  -- Example: Use this data to send events metrics to Datadog / New Relic.
  --  if conf.set_logger_metrics_in_ctx == true then
  --    helpers.set_logger_metrics(api_identifier, cb._state)
  --  end
  --  kong.log.notice("Circuit breaker state updated for route " .. api_identifier)
  --end
end

return CircuitBreakerHandler
