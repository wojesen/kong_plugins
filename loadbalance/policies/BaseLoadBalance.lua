---
--- Generated by EmmyLua(https://github.com/EmmyLua)
--- Created by wangjinshan.
--- DateTime: 2020/8/11 10:18
---
local BaseLoadBalance = {};
function BaseLoadBalance:new(o, name, conf)
  o = o or {}
  setmetatable(o, self);
  self.__index = self;
  self.conf = conf;
  self.name = name;
  return o;
end

function BaseLoadBalance:validate()
  return true, nil;
end

function BaseLoadBalance:get_upstream()
  return self.conf.loadbalance_upstream;
end

function BaseLoadBalance:handler(fallback)
  local validate, policy_loadbalance = self:validate();

  -- false fallback default upstream
  if not validate then
    fallback();
    return 'fallback', policy_loadbalance
  end
  -- uid upstream is not nil
  local _upstream = self:get_upstream()
  if policy_loadbalance and _upstream then
    kong.service.set_upstream(_upstream)
    kong.log.notice('loadbalance policy is ', policy_loadbalance, ',loadbalance upstream:', _upstream);
    return 'end', policy_loadbalance
  end
  return 'next', policy_loadbalance
end

return BaseLoadBalance;
