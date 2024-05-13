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
local reports = require "kong.reports"
local redis = require "resty.redis"


local kong = kong
local pairs = pairs
local null = ngx.null
local shm = ngx.shared.kong_rate_limiting_counters
local fmt = string.format
local cjson = require 'cjson'
local tonumber     = tonumber

local EMPTY_UUID = "00000000-0000-0000-0000-000000000000"


local function is_present(str)
  return str and str ~= "" and str ~= null
end


local function get_service_and_route_ids(conf)
  conf = conf or {}

  local service_id = conf.service_id
  local route_id   = conf.route_id

  if not service_id or service_id == null then
    service_id = EMPTY_UUID
  end

  if not route_id or route_id == null then
    route_id = EMPTY_UUID
  end

  return service_id, route_id
end


local get_local_key = function(conf, identifier, period, period_date)
  local service_id, route_id = get_service_and_route_ids(conf)

  return fmt("circuitbreaker:%s:%s:%s:%s:%s:%s",conf.limit_type, route_id, service_id, identifier,
             period_date, period)
end


local sock_opts = {}


local EXPIRATION = require "kong.plugins.rate-limiting.expiration"


local function get_redis_connection(conf)
  local red = redis:new()
  red:set_timeout(conf.redis_timeout)

  sock_opts.ssl = conf.redis_ssl
  sock_opts.ssl_verify = conf.redis_ssl_verify
  sock_opts.server_name = conf.redis_server_name

  -- use a special pool name only if redis_database is set to non-zero
  -- otherwise use the default pool name host:port
  sock_opts.pool = conf.redis_database and
                    conf.redis_host .. ":" .. conf.redis_port ..
                    ":" .. conf.redis_database
  local ok, err = red:connect(conf.redis_host, conf.redis_port,
                              sock_opts)
  if not ok then
    kong.log.err("failed to connect to Redis: ", err)
    return nil, err
  end

  local times, err = red:get_reused_times()
  if err then
    kong.log.err("failed to get connect reused times: ", err)
    return nil, err
  end

  if times == 0 then
    if is_present(conf.redis_password) then
      local ok, err
      if is_present(conf.redis_username) then
        ok, err = red:auth(conf.redis_username, conf.redis_password)
      else
        ok, err = red:auth(conf.redis_password)
      end

      if not ok then
        kong.log.err("failed to auth Redis: ", err)
        return nil, err
      end
    end

    if conf.redis_database ~= 0 then
      -- Only call select first time, since we know the connection is shared
      -- between instances that use the same redis database

      local ok, err = red:select(conf.redis_database)
      if not ok then
        kong.log.err("failed to change Redis database: ", err)
        return nil, err
      end
    end
  end

  return red
end


return {
  ["local"] = {
    increment = function(conf, limits, identifier, current_timestamp, value)
      local periods = timestamp.get_timestamps(current_timestamp)
      for period, period_date in pairs(periods) do
        if limits[period] then
          local cache_key = get_local_key(conf, identifier, period, period_date)
          local newval, err = shm:incr(cache_key, value, 0, EXPIRATION[period])
          if not newval then
            kong.log.err("could not increment counter for period '", period, "': ", err)
            return nil, err
          end
        end
      end

      return true
    end,
    usage = function(conf, identifier, period, current_timestamp)
      local periods = timestamp.get_timestamps(current_timestamp)
      local cache_key = get_local_key(conf, identifier, period, periods[period])

      local current_metric, err = shm:get(cache_key)
      if err then
        return nil, err
      end

      return current_metric or 0
    end
  },
  ["redis"] = {
    increment = function(conf, limits, identifier, current_timestamp, value)
      local red, err = get_redis_connection(conf)
      if not red then
        return nil, err
      end

      local keys = {}
      local expiration = {}
      local idx = 0
      local periods = timestamp.get_timestamps(current_timestamp)
      for period, period_date in pairs(periods) do
        if limits[period] then
          local cache_key = get_local_key(conf, identifier, period, period_date)
          local exists, err = red:exists(cache_key)
          if err then
            kong.log.err("failed to query Redis: ", err)
            return nil, err
          end
          local total =value
          local count =0
          if not exists or exists == 0 then
            total = 0
            count=0
          else
            local totalT, err = red:hmget(cache_key,"total")
            local countT, err = red:hmget(cache_key,"count")
            if totalT ~=nil and totalT ~= null and totalT[1] ~=nil and totalT[1] ~= null then
              total = totalT[1]
            end
            if countT ~=nil and countT ~= null and countT[1] ~=nil and countT[1] ~= null then
              count = countT[1]
            end
            --total = totalT[1]
            --count = countT[1]
            --current_metric.total = total
            --current_metric.count=count
            if err then
              kong.log.err("failed to query Redis: ", err)
              return nil, err
            end
          end
          --print_r({"wwwwwwwww"})
          --print_r({ current_metric })
          --print_r({"eeeeeeeeeeee"})
          --print_r({ count })
          --print_r({ total })
          --print_r({"fffffffff"})
          local currcount = tonumber(count)
          local currtotal = tonumber(total)
          count = currcount+ 1
          total = currtotal+value
          --if conf.ingnore ~=0 and count<=conf.ingnore then
          --  total=0
          --end
          idx = idx + 1
          keys[idx] = cache_key
          if not exists or exists == 0 then
            expiration[idx] = EXPIRATION[period]
          end

          red:init_pipeline()
          for i = 1, idx do
            --red:incrby(keys[i], value)
            red:hmset(keys[i],"total",total,"count",count)
            if expiration[i] then
              red:expire(keys[i], expiration[i])
            end
          end
        end
      end

      local _, err = red:commit_pipeline()
      if err then
        kong.log.err("failed to commit increment pipeline in Redis: ", err)
        return nil, err
      end

      local ok, err = red:set_keepalive(10000, 100)
      if not ok then
        kong.log.err("failed to set Redis keepalive: ", err)
        return nil, err
      end

      return true
    end,
    usage = function(conf, identifier, period, current_timestamp)
      local red, err = get_redis_connection(conf)
      if not red then
        return nil, err
      end

      reports.retrieve_redis_version(red)

      local periods = timestamp.get_timestamps(current_timestamp)
      local cache_key = get_local_key(conf, identifier, period, periods[period])

      local exists, err = red:exists(cache_key)
      if err then
        kong.log.err("failed to query Redis: ", err)
        return nil, err
      end
      local total =0
      local count =1
      if exists and exists ~=0 then
        --local current_metric, err = red:get(cache_key)
        local totalT, err = red:hmget(cache_key,"total")
        local countT, err = red:hmget(cache_key,"count")
        if err then
          return nil, err
        end
        if totalT ~=nil and totalT ~= null and totalT[1] ~=nil and totalT[1] ~= null then
          total = totalT[1]
        end
        if countT ~=nil and countT ~= null and countT[1] ~=nil and countT[1] ~= null then
          count = countT[1]
        end
      end

      local ok, err = red:set_keepalive(10000, 100)
      if not ok then
        kong.log.err("failed to set Redis keepalive: ", err)
      end

      return tonumber(tonumber(total)/tonumber(count)) or 0,tonumber(count)
    end
  }
}
