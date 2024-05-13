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


local Lplus = require "kong.plugins.sensitive-word-review.Lplus"
local ReadIlleagal = Lplus.Class("ReadIlleagal")

local def = ReadIlleagal.define

def.field("table").words = nil

def.static("string","=>", ReadIlleagal).ReadIlleagalWord = function(config)
    local readIlleagal = ReadIlleagal()
    readIlleagal:Init(config)
    return readIlleagal
end

--def.method().Init = function(self)
--    local file = io.open("illegal.txt", "r") -- 这里需要替换为真正的文件名或路径
--    if not file then
--        print("无法打开文件！")
--    else
--        local lines = {} -- 存放每一行的数组
--
--        local delimiter = "|"
--        local delimiterWord = ","
--        for line in file:lines() do
--
--            for match in (line..delimiter):gmatch("(.-)"..delimiter) do
--                if string.find(match, ",") then
--                    for matchWord in (match..delimiterWord):gmatch("(.-)"..delimiterWord) do
--                        table.insert(lines, matchWord)
--                    end
--                else
--                end
--
--            end
--        end
--        print(type(lines))
--        file:close() -- 关闭文件
--        self.words = lines
--    end
--end

def.method("string").Init = function(self,config)
    --print_r({"yyyyyyyyyyyyyyyyyyyyyyyyyyyy"})
    --print_r({config})
    --print_r({"uuuuuuuuuuuuuuuuuuuuuuuuuuu"})
    --local file = io.open("illegal.txt", "r") -- 这里需要替换为真正的文件名或路径
    --if not file then
    --    print("无法打开文件！")
    --else
    --    local lines = {} -- 存放每一行的数组
    --
    --    local delimiter = "|"
    --    local delimiterWord = ","
    --    for line in file:lines() do
    --
    --        for match in (line..delimiter):gmatch("(.-)"..delimiter) do
    --            if string.find(match, ",") then
    --                for matchWord in (match..delimiterWord):gmatch("(.-)"..delimiterWord) do
    --                    table.insert(lines, matchWord)
    --                end
    --            else
    --            end
    --
    --        end
    --    end
    --    print(type(lines))
    --    file:close() -- 关闭文件
    --    self.words = lines
    --end
    local lines = {}
    local delimiterWord = ","
    if string.find(config, ",") then
        for matchWord in (config..delimiterWord):gmatch("(.-)"..delimiterWord) do
            table.insert(lines, matchWord)
        end
    end
    self.words = lines
end
ReadIlleagal.Commit()
--_G.ReadIlleagal = ReadIlleagal
--local eeadIlleagalWord = ReadIlleagal.ReadIlleagalWord()
--for i, arr in ipairs(eeadIlleagalWord.words) do
--    print("第" .. i .. "行：" .. arr)
--end
return ReadIlleagal

-- 打开要读取的文件
--function getIlleagalWord()
--
--    local file = io.open("illegal.txt", "r") -- 这里需要替换为真正的文件名或路径
--    if not file then
--        print("无法打开文件！")
--    else
--        local lines = {} -- 存放每一行的数组
--
--        local delimiter = "|"
--        local delimiterWord = ","
--        for line in file:lines() do
--
--            for match in (line..delimiter):gmatch("(.-)"..delimiter) do
--                if string.find(match, ",") then
--                    for matchWord in (match..delimiterWord):gmatch("(.-)"..delimiterWord) do
--                        table.insert(lines, matchWord)
--                    end
--                else
--                end
--
--            end
--        end
--        print(type(lines))
--        file:close() -- 关闭文件
--        return lines
--        ---- 输出结果
--        --for i, arr in ipairs(lines) do
--        --    print("第" .. i .. "行：" .. arr)
--        --end
--    end
--end
