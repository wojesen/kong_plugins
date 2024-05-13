local typedefs = require "kong.db.schema.typedefs"


return {
  name = "sensitive-word-review",
  fields = {
    { protocols = typedefs.protocols },
    { config = {
        type = "record",
        fields = {
          { addSensitiveWords = { type = "string", default = "0" }, },
          { supplier = { type = "string", default = "local" }, },
          { useInit = { type = "boolean",  default = false }, },
        },
    }, },
  }
}
