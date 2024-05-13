local pl_template = require "pl.template"
local tx = require "pl.tablex"
local typedefs = require "kong.db.schema.typedefs"
local validate_header_name = require("kong.tools.utils").validate_header_name

local FILTER_TYPES = {
  "GET",
  "HEAD",
  "PUT",
  "PATCH",
  "POST",
  "DELETE",
  "OPTIONS",
  "TRACE",
  "CONNECT",
}
-- entries must have colons to set the key and value apart
local function check_for_value(entry)
  local name, value = entry:match("^([^:]+):*(.-)$")
  if not name or not value or value == "" then
    return false, "key '" ..name.. "' has no value"
  end

  local status, res, err = pcall(pl_template.compile, value)
  if not status or err then
    return false, "value '" .. value ..
            "' is not in supported format, error:" ..
            (status and res or err)
  end
  return true
end


local function validate_headers(pair, validate_value)
  local name, value = pair:match("^([^:]+):*(.-)$")
  if validate_header_name(name) == nil then
    return nil, string.format("'%s' is not a valid header", tostring(name))
  end

  if validate_value then
    if validate_header_name(value) == nil then
      return nil, string.format("'%s' is not a valid header", tostring(value))
    end
  end
  return true
end


local function validate_colon_headers(pair)
  return validate_headers(pair, true)
end


local strings_array = {
  type = "array",
  default = {},
  elements = { type = "string" },
}


local headers_array = {
  type = "array",
  default = {},
  elements = { type = "string", custom_validator = validate_headers },
}


local strings_array_record = {
  type = "record",
  fields = {
    { body = strings_array },
    { headers = headers_array },
    { querystring = strings_array },
  },
}


local colon_strings_array = {
  type = "array",
  default = {},
  elements = { type = "string", custom_validator = check_for_value }
}


local colon_header_value_array = {
  type = "array",
  default = {},
  elements = { type = "string", match = "^[^:]+:.*$", custom_validator = validate_headers },
}


local colon_strings_array_record = {
  type = "record",
  fields = {
    { body = colon_strings_array },
    { headers = colon_header_value_array },
    { querystring = colon_strings_array },
  },
}


local colon_headers_array = {
  type = "array",
  default = {},
  elements = { type = "string", match = "^[^:]+:.*$", custom_validator = validate_colon_headers },
}


local colon_rename_strings_array_record = {
  type = "record",
  fields = {
    { body = colon_strings_array },
    { headers = colon_headers_array },
    { querystring = colon_strings_array },
  },
}


local request_param_array_record = {
  type = "record",
  fields = {
    { data_type = {
      type = "string",
      required = true,
      one_of = { "string", "number"},
    }, },
    { request_key = {
      type = "string",
      required = true,
    }, },
    { not_null = {
      type = "boolean",
      required = true,
      default = true,
    }, },
    { default_value = {
      type = "string",
    }, },
  },
}

local request_headers_array = {
  type = "array",
  default = {},
  elements = request_param_array_record,
}

local request_paths_array = {
  type = "array",
  default = {},
  elements = request_param_array_record,
}

local request_querys_array = {
  type = "array",
  default = {},
  elements = request_param_array_record,
}

local request_bodys_array = {
  type = "array",
  default = {},
  elements = request_param_array_record,
}


local strings_request_record = {
  type = "record",
  fields = {
    { http_method = typedefs.http_method },
    { uri = {
      type = "string",
    }, },
    { content_type = {
      type = "string",
    }, },

    { headers = request_headers_array },
    { paths = request_paths_array },
    { querys = request_querys_array },
    { bodys = request_bodys_array },
  },
}



local backend_param_array_record = {
  type = "record",
  fields = {
    { data_type = {
      type = "string",
      required = true,
      one_of = { "string", "number"},
    }, },
    { request_key = {
      type = "string",
      required = true,
    }, },
    { request_position = {
      type = "string",
      required = true,
      one_of = { "header", "query", "path","body","constant" },
    }, },
    { default_value = {
      type = "string",
    }, },
    { backend_key = {
      type = "string",
    }, },
  },
}

local backend_headers_array = {
  type = "array",
  default = {},
  elements = backend_param_array_record,
}

local backend_paths_array = {
  type = "array",
  default = {},
  elements = backend_param_array_record,
}

local backend_querys_array = {
  type = "array",
  default = {},
  elements = backend_param_array_record,
}

local backend_bodys_array = {
  type = "array",
  default = {},
  elements = backend_param_array_record,
}


local strings_backend_record = {
  type = "record",
  fields = {
    { http_method = typedefs.http_method },
    { uri = {
      type = "string",
    }, },
    { content_type = {
      type = "string",
    }, },

    { headers = backend_headers_array },
    { paths = backend_paths_array },
    { querys = backend_querys_array },
    { bodys = backend_bodys_array },
  },
}

local default_headers_array = {
  type = "array",
  elements = { type = "string" },
}

local colon_strings_array_record_plus_uri = tx.deepcopy(colon_strings_array_record)
local uri = { uri = { type = "string" } }
table.insert(colon_strings_array_record_plus_uri.fields, uri)


return {
  name = "api-transformer",
  fields = {
    { config = {
        type = "record",
        fields = {
          { filter_type = {
            type = "string",
            default = "0",
            required = true,
            one_of = { "0", "1", "2" },
          }, },
          { default_headers  = default_headers_array },
          { request  = strings_request_record },
          { backend  = strings_backend_record },
        }
      },
    },
  }
}
