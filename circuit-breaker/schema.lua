local typedefs = require "kong.db.schema.typedefs"


local ORDERED_PERIODS = { "second", "minute", "hour", "day", "month", "year"}

local is_present = function(v)
  return type(v) == "string" and #v > 0
end

local function validate_periods_order(config)
  for i, lower_period in ipairs(ORDERED_PERIODS) do
    local v1 = config[lower_period]
    if type(v1) == "number" then
      for j = i + 1, #ORDERED_PERIODS do
        local upper_period = ORDERED_PERIODS[j]
        local v2 = config[upper_period]
        if type(v2) == "number" and v2 < v1 then
          return nil, string.format("The limit for %s(%.1f) cannot be lower than the limit for %s(%.1f)",
                                    upper_period, v2, lower_period, v1)
        end
      end
    end
  end

  if is_present(config.message)
          and(is_present(config.content_type)
          or is_present(config.body)) then
    return nil, "message cannot be used with content_type or body"
  end
  if is_present(config.content_type)
          and not is_present(config.body) then
    return nil, "content_type requires a body"
  end
  if config.echo and (
          is_present(config.content_type) or
                  is_present(config.body)) then
    return nil, "echo cannot be used with content_type and body"
  end

  return true
end


local function is_dbless()
  local _, database, role = pcall(function()
    return kong.configuration.database,
           kong.configuration.role
  end)

  return database == "off" or role == "control_plane"
end


local policy
if is_dbless() then
  policy = {
    type = "string",
    default = "local",
    len_min = 0,
    one_of = {
      "local",
      "redis",
    },
  }

else
  policy = {
    type = "string",
    default = "redis",
    len_min = 0,
    one_of = {
      "local",
      "redis",
    },
  }
end


return {
  name = "circuit-breaker",
  fields = {
    { protocols = typedefs.protocols_http },
    { config = {
        type = "record",
        fields = {
          { second = { type = "number", gt = 0 }, },
          { minute = { type = "number", gt = 0 }, },
          { hour = { type = "number", gt = 0 }, },
          { day = { type = "number", gt = 0 }, },
          { month = { type = "number", gt = 0 }, },
          { year = { type = "number", gt = 0 }, },
          { limit_by = {
              type = "string",
              default = "consumer",
              one_of = { "consumer", "credential", "ip", "service", "header", "path" },
          }, },
          { limit_type = {
            type = "string",
            default = "latency",
            one_of = { "latency", "error" },
          }, },
          { header_name = typedefs.header_name },
          { path = typedefs.path },
          { policy = policy },
          { fault_tolerant = { type = "boolean", required = true, default = true }, },
          { redis_host = typedefs.host },
          { redis_port = typedefs.port({ default = 6379 }), },
          { redis_password = { type = "string", len_min = 0, referenceable = true }, },
          { redis_username = { type = "string", referenceable = true }, },
          { redis_ssl = { type = "boolean", required = true, default = false, }, },
          { redis_ssl_verify = { type = "boolean", required = true, default = false }, },
          { redis_server_name = typedefs.sni },
          { redis_timeout = { type = "number", default = 2000, }, },
          { redis_database = { type = "integer", default = 0 }, },
          { hide_client_headers = { type = "boolean", required = true, default = false }, },
          { status_code = {
            type = "integer",
            default = 503,
            between = { 100, 599 },
          }, },
          { message = { type = "string" }, },
          { content_type = { type = "string" }, },
          { body = { type = "string" }, },
          { echo = { type = "boolean", required = true, default = false }, },
          { ingnore = { type = "number",required = true ,default = 0}, },
          { latency_threshold = { type = "number",required = true ,default = 0}, },
        },
        custom_validator = validate_periods_order,
      },
    },
  },
  entity_checks = {
    { at_least_one_of = { "config.second", "config.minute", "config.hour", "config.day", "config.month", "config.year" } },
    { conditional = {
      if_field = "config.policy", if_match = { eq = "redis" },
      then_field = "config.redis_host", then_match = { required = true },
    } },
    { conditional = {
      if_field = "config.policy", if_match = { eq = "redis" },
      then_field = "config.redis_port", then_match = { required = true },
    } },
    { conditional = {
      if_field = "config.limit_by", if_match = { eq = "header" },
      then_field = "config.header_name", then_match = { required = true },
    } },
    { conditional = {
      if_field = "config.limit_by", if_match = { eq = "path" },
      then_field = "config.path", then_match = { required = true },
    } },
    { conditional = {
      if_field = "config.policy", if_match = { eq = "redis" },
      then_field = "config.redis_timeout", then_match = { required = true },
    } },
  },
}
