local timestamp = require "kong.tools.timestamp"
local cassandra = require "cassandra"


local kong = kong
local concat = table.concat
local pairs = pairs
local floor = math.floor
local fmt = string.format
local tonumber = tonumber
local tostring = tostring

local find_pk = {}
local function find(identifier)
    find_pk.identifier  = identifier
    return kong.db.sensitive_word:select(find_pk)
end
return {
    find        = find,
}