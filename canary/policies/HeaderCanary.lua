---
--- Generated by EmmyLua(https://github.com/EmmyLua)
--- Created by wangjinshan.
--- DateTime: 2020/08/14 16:21
---

local utils = require 'kong.plugins.canary';
local cjson = require "cjson"
local cmatch = require 'kong.plugins.canary.policies.cmatch';
local BaseCanary = require 'kong.plugins.canary.policies.BaseCanary';

local policy = "header";

local HeaderCanary = BaseCanary:new();

function HeaderCanary:new(o, conf)
  o = o or BaseCanary:new(o, policy, conf)
  setmetatable(o, self);
  self.__index = self;
  return o;
end

function HeaderCanary:handler(fallback)
  if not self.conf.header or #self.conf.header == 0 then
    return 'next', policy
  end

  local headers = self.conf.header
  for i = 1, #headers do
    if headers[i].name and headers[i].range and #headers[i].range>0 then
      local values = utils[policy].getValue(headers[i].name)
      kong.log.notice('conf.name:', headers[i].name, ',value:', cjson.encode(values))
      if type(values) == 'string' then
        if cmatch.match(headers[i].range, values, headers[i].matchType) then
          kong.service.set_target(headers[i].upstream.host,headers[i].upstream.port)
          kong.log.notice('Canary policy is ', policy, ',Canary host:', headers[i].upstream.host);
          return 'end', policy
        end
      elseif type(values) == 'table' then
        for _, v in ipairs(values) do
          if cmatch.match(headers[i].range, v, headers[i].matchType) then
            kong.service.set_target(headers[i].upstream.host,headers[i].upstream.port)
            kong.log.notice('Canary policy is ', policy, ',Canary host:', headers[i].upstream.host);
            return 'end', policy
          end
        end
      end
    end
  end

  -- uid upstream is not nil
  return 'next', policy
end

return HeaderCanary;
