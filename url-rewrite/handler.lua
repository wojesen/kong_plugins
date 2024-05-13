local URLRewriter = {
  PRIORITY = 700,
  VERSION = "1.3.0"
}

function split(s, delimiter)
  local result = {}
  for match in (s..delimiter):gmatch("(.-)"..delimiter) do
      table.insert(result, match)
  end
  return result
end

function resolveUrlParams(requestParams, url)
  for paramValue in requestParams do
    local requestParamValue = ngx.ctx.router_matches.uri_captures[paramValue]
    if type(requestParamValue) == 'string' then
      requestParamValue = requestParamValue:gsub("%%", "%%%%")
    end
    url = url:gsub("<" .. paramValue .. ">", requestParamValue)
  end
  return url
end

function getRequestUrlParams(url)
  return string.gmatch(url, "<(.-)>")
end

function URLRewriter:access(config)
  if config.query_string ~= nil then
    local args = ngx.req.get_uri_args()
    for k, queryString in ipairs(config.query_string) do
      local splitted = split(queryString, '=')
      local key, value = splitted[1], splitted[2]
      local queryParams = getRequestUrlParams(value)
      local resolvedParams = resolveUrlParams(queryParams, value)
      args[key] = resolvedParams
    end
    ngx.req.set_uri_args(args)
  end

  local requestParams = getRequestUrlParams(config.url)
  local url = resolveUrlParams(requestParams, config.url)

  local service_path = ngx.ctx.service.path or ""
  if service_path ~= "" then
    url = service_path..url
  end

  ngx.var.upstream_uri = url
end

return URLRewriter
