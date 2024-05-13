-- Copyright (C) Kong Inc.
require "kong.tools.utils" -- ffi.cdefs
local ngx = ngx


local ManagementMetaHandler = {
  PRIORITY = 9,
  VERSION = "1.1.0",
}
function ManagementMetaHandler:body_filter(conf)
  if conf then
    ngx.ctx.envId = conf.envId
    ngx.ctx.envName = conf.envName
    ngx.ctx.groupId = conf.groupId
    ngx.ctx.groupName = conf.groupName
    ngx.ctx.apiId = conf.apiId
    ngx.ctx.apiName = conf.apiName
    ngx.ctx.namespace = conf.namespace
  end
end
return ManagementMetaHandler
