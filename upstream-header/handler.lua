local kong = kong
local set_headers = kong.service.request.set_headers
local ngx = ngx
local decode_base64 = ngx.decode_base64
local UpstreamHeaderHandler = {
  VERSION  = "1.3.0",
  PRIORITY = 801,
}


function UpstreamHeaderHandler:access(conf)
  if conf.upstream_headers == nil or #conf.upstream_headers == 0 then
    return
  end
  local headers = {}
  for i = 1, #conf.upstream_headers do
    headers[conf.upstream_headers[i].header_key] = decode_base64(conf.upstream_headers[i].header_value)
  end
  set_headers(headers)
end


return UpstreamHeaderHandler
