local typedefs = require "kong.db.schema.typedefs"


return {
  name = "file-log",
  fields = {
    { protocols = typedefs.protocols },
    { config = {
        type = "record",
        fields = {
          { path = { type = "string",
                     required = true,
                     match = [[^[^*&%%\`]+$]],
                     err = "not a valid filename",
          }, },
          { reopen = { type = "boolean", required = true, default = false }, },
          { custom_fields_by_lua = typedefs.lua_code },
          { envId = { type = "string", default = "0" }, },
          { envName = { type = "string", default = "0" }, },
          { groupId = { type = "string", default = "0" }, },
          { groupName = { type = "string", default = "0" }, },
          { apiId = { type = "string", default = "0" }, },
          { apiName = { type = "string", default = "0" }, },
          { host = { type = "string", default = "0" }, },
        },
    }, },
  }
}
