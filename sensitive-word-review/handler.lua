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
local wordFilter = require "kong.plugins.sensitive-word-review.wordFilter"
local getBodyContent = require "kong.plugins.sensitive-word-review.getBodyContent"
local ngx = ngx
local kong = kong
local concat = table.concat
local lower = string.lower
local find = string.find
local cjson = require "cjson.safe"
local utils = require("kong.tools.utils")
local inflate_gzip = utils.inflate_gzip

local SensitiveWordReviewHandler = {
  PRIORITY = 9,
  VERSION = "1.1.0",
}
local function is_json_body(content_type)
  return content_type and find(lower(content_type), "application/json", nil, true)
end

local function read_json_body(body)
  if body then
    return cjson.decode(body)
  end
end

function SensitiveWordReviewHandler:body_filter(conf)
  if conf.addSensitiveWords == nil or conf.addSensitiveWords =="" then
    return
  end
  if is_json_body(kong.response.get_header("Content-Type")) then
    local ctx = ngx.ctx
    local chunk, eof = ngx.arg[1], ngx.arg[2]

    ctx.rt_body_chunks = ctx.rt_body_chunks or {}
    ctx.rt_body_chunk_number = ctx.rt_body_chunk_number or 1

    if eof then
      local chunks = concat(ctx.rt_body_chunks)
      local encode = kong.response.get_header("content-encoding")
      local json_body
      if encode and encode == "gzip" then
        local inflateGzip = inflate_gzip(chunks)
        json_body = read_json_body(inflateGzip)
      else
        json_body = read_json_body(chunks)
      end
      local flag = false
      if json_body and type(json_body) =="table" and json_body["choices"] ~= nil and type(json_body["choices"]) =="table" and #json_body["choices"] >0 then
        for i = 1, #json_body["choices"] do
          if json_body["choices"][i] ~= nil and type(json_body["choices"][i]) == 'table' and json_body["choices"][i].text ~=nil and type(json_body["choices"][i].text) == 'string' then
            local acResult,test12 = wordFilter.findSensitiveWords(conf,json_body["choices"][i].text)
            if acResult ~=nil and acResult ~= "" then
              json_body["choices"][i].text = test12
              flag = true
            end
          end
        end
        if flag then
          return kong.response.set_raw_body(cjson.encode(json_body))
        end
      end
      ngx.arg[1] = chunks

    else
      ctx.rt_body_chunks[ctx.rt_body_chunk_number] = chunk
      ctx.rt_body_chunk_number = ctx.rt_body_chunk_number + 1
      ngx.arg[1] = nil
    end
  end
end

function SensitiveWordReviewHandler:access(conf)
  if conf.addSensitiveWords == nil or conf.addSensitiveWords =="" then
    return
  end
  local words = getBodyContent.getRequestContent()
  if words == nil or words == "" then
    return
  end
  local acResult,test12 = wordFilter.findSensitiveWords(conf,words)
  --print_r({"vvvvvvvvvvvvvvvvv555555555555555222"})
  --print_r({acResult})
  --print_r({"vvvvvvvvvvvvvvvv666666666666666662222"})
  if acResult ~=nil and acResult ~= "" then
    local status = 422
    return kong.response.error(status, "request have illegal text")
  end
end
function SensitiveWordReviewHandler:log(conf)
  ngx.shared.ACTrie =nil
end
return SensitiveWordReviewHandler
