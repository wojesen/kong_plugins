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
      --print_r({"xxxxxxxxxxxxxxxxxxxx"})
      --print_r({json_body})
      --print_r({"ccccccccccccccccccccccccc"})
      --print_r({"xxxxxxxxxxxxxxxxxxxx222222222222222222"})
      --print_r({type(json_body["choices"])})
      --print_r({"ccccccccccccccccccccccccc22222222222222222222222"})
      local flag = false
      if json_body and json_body["choices"] ~= nil and type(json_body["choices"]) =="table" and #json_body["choices"] >0 then
        for i = 1, #json_body["choices"] do
          --print_r({"dddddddddddddddddddddddddddddd333333333333"})
          --print_r({type(json_body["choices"][i])})
          --print_r({"ffffffffffffffffffffffff33333333333333333"})
          if json_body["choices"][i] ~= nil and type(json_body["choices"][i]) == 'table' and json_body["choices"][i].text ~=nil and type(json_body["choices"][i].text) == 'string' then
            local acResult,test12 = wordFilter.findSensitiveWords(conf,json_body["choices"][i].text)
            --print_r({"qqqqqqqqqqqqqqqqqqqqq77777777777777777777777"})
            --print_r({acResult})
            --print_r({"qqqqqqqqqqqqqqqqqqqqq666666666666666662222"})
            --print_r({"qqqqqqqqqqqqqqqqqqqqq888888888888888888"})
            --print_r({test12})
            --print_r({"qqqqqqqqqqqqqqqqqqqqq88888888888888888888"})
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
  --local row, err = pghandler.find("init")
  --if err then
  --  return nil, err
  --end
  ----if row and row.value ~= null then
  ----  return row.value
  ----end
  --local initSensitiveWords = ngx.shared.addSensitiveWords
  --if initSensitiveWords == nil then
  --  print_r({"6666666666666666666666666666666666666666666666666666666"})
  --  ngx.shared.addSensitiveWords = conf.addSensitiveWords
  --end
  --local ACTrie = ngx.shared.ACTrie
  --print_r({"7777777777777777777777777777"})
  --print_r({ACTrie})
  --print_r({"888888888888888"})
  --print_r({conf.addSensitiveWords})
  --print_r({"99999999999999999999999999"})
  --print_r({ngx.shared.addSensitiveWords})
  --print_r({"555555555555555555555555555"})
  --if ACTrie == nil or conf.addSensitiveWords ~= initSensitiveWords then
  --  ngx.shared.addSensitiveWords = conf.addSensitiveWords
  --  local words = row.value
  --  if conf.addSensitiveWords ~= "0" then
  --    words = row.value .. "," .. conf.addSensitiveWords
  --  end
  --  local block_words_data = {}
  --  block_words_data = require "kong.plugins.sensitive-word-review.ReadIlleagal".ReadIlleagalWord(words).words
  --  ACTrie = require "kong.plugins.sensitive-word-review.ACTrie".CreateACTrie()
  --  print_r({"zzzzzzzzz555555555555555"})
  --  print_r({#block_words_data})
  --  print_r({"zzzz66666666666666666"})
  --  if block_words_data then
  --    local len = #block_words_data
  --    for i = 1, len do
  --      ACTrie:Insert(block_words_data[i], i)
  --    end
  --  end
  --  ACTrie:BuildFail()
  --  ngx.shared.ACTrie = ACTrie
  --  --print_r({"zzzz88888888888888888"})
  --  --local testStr = "我爱  吃饭的事情大概大家都知道，我爱摸鱼的事情我觉得大家也都清楚的 贱人  我草"
  --  --local acResult,test12 = ACTrie:FilterBlockedWords(testStr)
  --  --print_r({"qqqqqqqqqqqqqqqqqqqqq555555555555555"})
  --  --print_r({acResult})
  --  --print_r({"qqqqqqqqqqqqqqqqqqqqq66666666666666666"})
  --end
  --local testStr = "我爱  吃饭的事情大概大家都知道，我爱摸鱼的事情我觉得大家也都清楚的 贱人  我草"
  --local acResult,test12 = ACTrie:FilterBlockedWords(testStr)
  --print_r({"qqqqqqqqqqqqqqqqqqqqq555555555555555222"})
  --print_r({acResult})
  --print_r({"qqqqqqqqqqqqqqqqqqqqq666666666666666662222"})

end
function SensitiveWordReviewHandler:log(conf)
  ngx.shared.ACTrie =nil
end
return SensitiveWordReviewHandler
