local typedefs = require 'kong.db.schema.typedefs'

return {
  name = "kong-plugin-url-rewrite",
  fields = {
    { consumer = typedefs.no_consumer, },
    {
      config = {
        type = "record",
        fields = {
          { url = { required = true, type = "string" }, },
          { query_string = { required = false, type = "array", elements = { type = "string" } } },
        }
      }
    }
  }
}
