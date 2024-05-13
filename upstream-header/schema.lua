local pl_template = require "pl.template"
local tx = require "pl.tablex"
local typedefs = require "kong.db.schema.typedefs"
local validate_header_name = require("kong.tools.utils").validate_header_name

local upstream_param_array_record = {
  type = "record",
  fields = {
    { header_key = {
      type = "string",
      required = true,
    }, },
    { header_value = {
      type = "string",
      required = true,
    }, },
  },
}

local upstream_headers_array = {
  type = "array",
  default = {},
  elements = upstream_param_array_record,
}

return {
  name = "upstream-header",
  fields = {
    { config = {
        type = "record",
        fields = {
          { upstream_headers  = upstream_headers_array },
        }
      },
    },
  }
}
