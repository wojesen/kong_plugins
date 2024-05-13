local typedefs = require "kong.db.schema.typedefs"
local function validate_shared_dict()
  if not ngx.shared.prometheus_metrics then
    return nil,
           "ngx shared dict 'prometheus_metrics' not found"
  end
  return true
end


return {
  name = "prometheus",
  fields = {
    { config = {
        type = "record",
        fields = {
          { per_consumer = { type = "boolean", default = false }, },
          { http_endpoint = typedefs.url({ required = true }) },
          { method = { type = "string", default = "POST", one_of = { "POST", "PUT", "PATCH", "GET"  }, }, },
          { content_type = { type = "string", default = "application/json", one_of = { "application/json" }, }, },
          { timeout = { type = "number", default = 10000 }, },
          { keepalive = { type = "number", default = 60000 }, },
        },
        custom_validator = validate_shared_dict,
    }, },
  },
}
