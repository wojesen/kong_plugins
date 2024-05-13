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
---
--- Generated by Luanalysis
--- Created by wang.jinshan3.
--- DateTime: 2024/1/11 15:38
---
local ngx = ngx
local cjson = require "cjson.safe"
local kong = kong

local function parse_json(body)
    if body then
        local status, res = pcall(cjson.decode, body)
        if status then
            return res
        end
    end
end

function getRequestContent()
    local rawbody = kong.request.get_raw_body()
    local body = parse_json(rawbody)
    --print_r({"dddddddddddddddddddddddddddddd"})
    --print_r({body["messages"]})
    --print_r({"ffffffffffffffffffffffff"})
    local msg = body["messages"]
    if msg == nil or msg == "" or #msg<1 then
        return nil
    end
    local str = ""
    for i = 1, #msg do
        --print_r({"dddddddddddddddddddddddddddddd333333333333"})
        --print_r({type(msg[i])})
        --print_r({"ffffffffffffffffffffffff33333333333333333"})
        if msg[i] ~= nil and type(msg[i]) == 'table' and msg[i].content ~=nil and type(msg[i].content) == 'string' then
            str = str .. msg[i].content
        end
    end
    --print_r({"dddddddddddddddddddddddddddddd2222222222222"})
    --print_r({str})
    --print_r({"ffffffffffffffffffffffff22222222222222222"})
    return str
end
return {
    getRequestContent        = getRequestContent,
}
