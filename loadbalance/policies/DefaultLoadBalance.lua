---
--- Generated by EmmyLua(https://github.com/EmmyLua)
--- Created by wangjinshan.
--- DateTime: 2020/8/11 10:18
---

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


local cjson = require "cjson"
local BaseLoadBalance = require 'kong.plugins.loadbalance.policies.BaseLoadBalance';
local policy = 'default'
local DefaultLoadBalance = BaseLoadBalance:new()
function DefaultLoadBalance:new(o, conf)
  o = o or BaseLoadBalance:new(o, policy, conf)
  setmetatable(o, self);
  self.__index = self;
  return o;
end

function DefaultLoadBalance:validate()
  return true, self.name
end

function parse_json(body)
  if body then
    local status, res = pcall(cjson.decode, body)
    if status then
      return res
    end
  end
end

function DefaultLoadBalance:get_upstream()
  local upstreams = self.conf.loadbalance_upstream
  if upstreams and #upstreams>0 then
    if #upstreams == 1 then
      return upstreams[1].host,upstreams[1].port
    else
      local count = math.random(#upstreams)
      return upstreams[count].host,upstreams[count].port
    end
  end
  return nil;
end

function DefaultLoadBalance:handler(fallback)
  local validate, policy_loadbalance = self:validate();

  -- false fallback default upstream
  if not validate then
    fallback();
    return 'fallback', policy_loadbalance
  end
  -- uid upstream is not nil
  local _host,_port = self:get_upstream()
  if _host and _port then
    kong.service.set_target(_host,_port)
    kong.log.notice('loadbalance policy is ', policy_loadbalance, ',loadbalance host:', _host);
    return 'end', policy_loadbalance
  end
end

return DefaultLoadBalance
