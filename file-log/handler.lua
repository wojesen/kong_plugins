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

-- Copyright (C) Kong Inc.
require "kong.tools.utils" -- ffi.cdefs


local ffi = require "ffi"
local cjson = require "cjson"
local system_constants = require "lua_system_constants"
local sandbox = require "kong.tools.sandbox".sandbox
local body_transformer = require "kong.plugins.response-transformer.body_transformer"
local is_json_body = body_transformer.is_json_body
local utils = require("kong.tools.utils")
local inflate_gzip = utils.inflate_gzip
local concat = table.concat
local ngx = ngx
local kong = kong
local kong_dict = ngx.shared.kong
--local buffer = require "string.buffer"

local O_CREAT = system_constants.O_CREAT()
local O_WRONLY = system_constants.O_WRONLY()
local O_APPEND = system_constants.O_APPEND()
local S_IRUSR = system_constants.S_IRUSR()
local S_IWUSR = system_constants.S_IWUSR()
local S_IRGRP = system_constants.S_IRGRP()
local S_IROTH = system_constants.S_IROTH()


local oflags = bit.bor(O_WRONLY, O_CREAT, O_APPEND)
local mode = ffi.new("int", bit.bor(S_IRUSR, S_IWUSR, S_IRGRP, S_IROTH))


local sandbox_opts = { env = { kong = kong, ngx = ngx } }


local C = ffi.C

local function read_json_body(body)
  if body then
    return cjson.decode(body)
  end
end
-- fd tracking utility functions
local file_descriptors = {}

-- Log to a file.
-- @param `conf`     Configuration table, holds http endpoint details
-- @param `message`  Message to be logged
local function log(conf, message)
  if conf and message then
    message.envId = conf.envId
    message.envName = conf.envName
    message.groupId = conf.groupId
    message.groupName = conf.groupName
    message.apiId = conf.apiId
    message.apiName = conf.apiName
    message.host = conf.host
    message.total_tokens = ngx.ctx.total_tokens
    message.prompt_tokens = ngx.ctx.prompt_tokens
    message.completion_tokens = ngx.ctx.completion_tokens
  end
  local msg = cjson.encode(message) .. "\n"
  local fd = file_descriptors[conf.path]

  if fd and conf.reopen then
    -- close fd, we do this here, to make sure a previously cached fd also
    -- gets closed upon dynamic changes of the configuration
    C.close(fd)
    file_descriptors[conf.path] = nil
    fd = nil
  end

  if not fd then
    fd = C.open(conf.path, oflags, mode)
    if fd < 0 then
      local errno = ffi.errno()
      kong.log.err("failed to open the file: ", ffi.string(C.strerror(errno)))

    else
      file_descriptors[conf.path] = fd
    end
  end

  C.write(fd, msg, #msg)
end


local FileLogHandler = {
  PRIORITY = 9,
  VERSION = "2.1.0",
}


function FileLogHandler:log(conf)
  local response_body, err = kong_dict:get("test")
  print_r({"eeeeeeeeeeeeeeeeeeeeeeeeee"})
  print_r({response_body})
  print_r({"ffffffffffffffffffffffffff"})
  if conf.custom_fields_by_lua then
    local set_serialize_value = kong.log.set_serialize_value
    for key, expression in pairs(conf.custom_fields_by_lua) do
      set_serialize_value(key, sandbox(expression, sandbox_opts)())
    end
  end

  local message = kong.log.serialize()
  log(conf, message)
end

--function FileLogHandler:body_filter(conf)
--  --local ok, err = kong_dict:add(DECLARATIVE_LOCK_KEY, 0, 60)
--
--  local response_body, err = kong_dict:get("test")
--  print_r({"11111111111111111111111111111111"})
--  print_r({response_body})
--  print_r({"22222222222222222222222222222222222"})
--  if err then
--    local ok, err = kong_dict:safe_set("test", "", 60)
--  end
--  if not response_body then
--    response_body = ""
--    local ok, err = kong_dict:safe_set("test", response_body, 60)
--  end
--  --local body_buffer = ngx.ctx.response_body
--  local chunk = ngx.arg[1]
--  --if type(chunk) == "string" and chunk ~= "" then
--    --if not body_buffer then
--    --  body_buffer = ""
--    --  ngx.ctx.response_body = body_buffer
--    --end
--    --if not ngx.arg[2] then
--      print_r({"mmmmmmmmmmmmmmmmmmmmmmmmmmm"})
--      print_r({chunk})
--      print_r({"nnnnnnnnnnnnnnnnnnnnnnnnnn"})
--      response_body= response_body .. chunk
--      --ngx.ctx.response_body = body_buffer
--      print_r({"hhhhhhhhhhhhhhhhhhhhh"})
--      print_r({response_body})
--      print_r({"jjjjjjjjjjjjjjjjjjjjjj"})
--      local ok, err = kong_dict:safe_set("test", response_body, 60)
--    --end
--  --end
--end

return FileLogHandler
