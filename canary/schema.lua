---
--- Generated by EmmyLua(https://github.com/EmmyLua)
--- Created by wangjinshan.
--- DateTime: 2020/08/14 16:21
---
local typedefs = require "kong.db.schema.typedefs"
local MATCHS = {
    "all-match",
    "prefix",
    "regex",
}
local string_array = {
  type = "array",
  default = {},
  elements = { type = "string" },
}

local ip_string_array = {
  type = "array",
  default = {},
  --elements = { type = "string", },
  elements = typedefs.cidr_v4,
}

local header_string_array = {
  type = "array",
  default = {},
  --elements = { type = "string", },
  elements = { type = "record",
               fields = {
                 { range = string_array },
               },
  },
}

local query_string_array = {
  type = "array",
  default = {},
  --elements = { type = "string", },
  elements = { type = "record",
               fields = {
                 { range = string_array },
               },
  },
}

local cookie_string_array = {
  type = "array",
  default = {},
  --elements = { type = "string", },
  elements = { type = "record",
               fields = {
                 { range = string_array },
               },
  },
}

local ip_array = {
  type = "array",
  elements = { type = "record",
               fields = {
                 { range = ip_string_array },
                 { upstream = { type = "record",
                                fields = {
                                  { host = { type = "string", required = true }, },
                                  { port = { type = "number", required = true }, },
                                },
                               },
                 },
               },
  },
}

local header_array = {
  type = "array",
  elements = { type = "record",
               fields = {
                 { name = { type = "string", required = true }, },
                 { matchType = { type = "string", default = "all-match",one_of = MATCHS,required = true }, },
                 { range = string_array },
                 { upstream = { type = "record",
                                fields = {
                                  { host = { type = "string", required = true }, },
                                  { port = { type = "number", required = true }, },
                                },
                              },
                 },
               },
  },
}

local query_array = {
  type = "array",
  elements = { type = "record",
               fields = {
                 { name = { type = "string", required = true }, },
                 { matchType = { type = "string", default = "all-match",one_of = MATCHS,required = true }, },
                 { range = string_array },
                 { upstream = { type = "record",
                                fields = {
                                  { host = { type = "string", required = true }, },
                                  { port = { type = "number", required = true }, },
                                },
                 },
                 },
               },
  },
}

local cookie_array = {
  type = "array",
  elements = { type = "record",
               fields = {
                 { name = { type = "string", required = true }, },
                 { matchType = { type = "string", default = "all-match",one_of = MATCHS,required = true }, },
                 { range = string_array },
                 { upstream = { type = "record",
                                fields = {
                                  { host = { type = "string", required = true }, },
                                  { port = { type = "number", required = true }, },
                                },
                 },
                 },
               },
  },
}

return {
  name = "canary",
  fields = {
    { protocols = typedefs.protocols_http },
    { config = {
      type = "record",
      fields = {
        { ip = ip_array },
        { header = header_array },
        { query = query_array },
        { cookie = cookie_array },
      },
    },
    },
  },
}
