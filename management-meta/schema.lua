local typedefs = require "kong.db.schema.typedefs"


return {
  name = "management-meta",
  fields = {
    { protocols = typedefs.protocols },
    { config = {
        type = "record",
        fields = {
          { envId = { type = "string", default = "0" }, },
          { envName = { type = "string", default = "0" }, },
          { groupId = { type = "string", default = "0" }, },
          { groupName = { type = "string", default = "0" }, },
          { apiId = { type = "string", default = "0" }, },
          { apiName = { type = "string", default = "0" }, },
          { namespace = { type = "string", default = "0" }, },
        },
    }, },
  }
}
