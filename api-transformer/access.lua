local multipart = require "multipart"
local cjson = require "cjson"
local pl_template = require "pl.template"
local pl_tablex = require "pl.tablex"

local table_insert = table.insert
local get_uri_args = kong.request.get_query
local set_uri_args = kong.service.request.set_query
local clear_header = kong.service.request.clear_header
local get_header = kong.request.get_header
local set_header = kong.service.request.set_header
local get_headers = kong.request.get_headers
local set_headers = kong.service.request.set_headers
local set_method = kong.service.request.set_method
local get_raw_body = kong.request.get_raw_body
local set_raw_body = kong.service.request.set_raw_body
local encode_args = ngx.encode_args
local ngx_decode_args = ngx.decode_args
local type = type
local str_find = string.find
local pcall = pcall
local pairs = pairs
local error = error
local rawset = rawset
local pl_copy_table = pl_tablex.deepcopy
local gsub = string.gsub



local print = print
local tconcat = table.concat
local tinsert = table.insert
local srep = string.rep
local tostring = tostring
local next = next

function print_r(root)
  local cache = {  [root] = "." }
  local function _dump(t,space,name)
    local temp = {}
    for k,v in pairs(t) do
      local key = tostring(k)
      if cache[v] then
        tinsert(temp,"+" .. key .. " {" .. cache[v].."}")
      elseif type(v) == "table" then
        local new_key = name .. "." .. key
        cache[v] = new_key
        tinsert(temp,"+" .. key .. _dump(v,space .. (next(t,k) and "|" or " " ).. srep(" ",#key),new_key))
      else
        tinsert(temp,"+" .. key .. " [" .. tostring(v).."]")
      end
    end
    return tconcat(temp,"\n"..space)
  end
  print(_dump(root, "",""))
end

local _M = {}

local DEBUG = ngx.DEBUG
local CONTENT_LENGTH = "content-length"
local CONTENT_TYPE = "content-type"
local HOST = "host"
local JSON, MULTI, ENCODED = "json", "multi_part", "form_encoded"
local EMPTY = pl_tablex.readonly({})

local function parse_json(body)
  if body then
    local status, res = pcall(cjson.decode, body)
    if status then
      return res
    end
  end
end

local function decode_args(body)
  if body then
    return ngx_decode_args(body)
  end
  return {}
end

local function get_content_type(content_type)
  if content_type == nil then
    return
  end
  if str_find(content_type:lower(), "application/json", nil, true) then
    return JSON
  elseif str_find(content_type:lower(), "multipart/form-data", nil, true) then
    return MULTI
  elseif str_find(content_type:lower(), "application/x-www-form-urlencoded", nil, true) then
    return ENCODED
  end
end

local function reverse_table(tab)
  local revtab = {}
  for k, v in pairs(tab) do
    revtab[v] = k
  end
  return revtab
end

local function request_iter(config_array)
  return function(config_array, i, previous_name, previous_value)
    i = i + 1
    local ele = config_array[i]
    if ele == nil then -- n + 1
      return nil
    end

    return i, ele.request_key, ele
  end, config_array, 0
end

local function backend_iter(config_array)
  return function(config_array, i, previous_name, previous_value)
    i = i + 1
    local ele = config_array[i]
    if ele == nil then -- n + 1
      return nil
    end

    return i, ele.backend_key, ele
  end, config_array, 0
end

local function path_params(request_path, real_path, param_array)
  if not request_path or not next(param_array) then
    return
  end

  local params_map = {}
  local key_list = {}
  local value_list = {}

  --参数key的list
  for k in string.gmatch(request_path, "([^/]+)") do
    table.insert(key_list, k)
  end

  --翻转key_list
  key_list = reverse_table(key_list)

  --提取的value的list
  for v in string.gmatch(real_path, "([^/]+)") do
    local str = v
    --如果参数值经过urlEncode处理，则进行urlDecode.(转换后的请求到kong时也会被urlEncode)
    if string.find(str, "%%") ~= nil then
      str = decodeURI(str)
    end
    table.insert(value_list, str)
  end

  for i = 1, #param_array do
    if param_array[i] ~= nil and param_array[i].request_key ~= nil then
      local param = param_array[i].request_key
      local pattern = "[" .. param .. "]"
      local pos = key_list[pattern]
      params_map[param] = value_list[pos]
    end
  end
  return params_map
end

local function getValueFromMapping(params_map,request_table)
  if params_map == nil or params_map.request_position ==nil or params_map.request_key == nil then
    return nil
  end
  if params_map.request_position == "header" then
    return request_table.header[params_map.request_key] or request_table.params[params_map.request_key].default_value
  end

  if params_map.request_position == "query" then
    return request_table.query[params_map.request_key] or request_table.params[params_map.request_key].default_value
  end

  if params_map.request_position == "body" then
    if request_table.content_type == ENCODED or request_table.content_type == JSON then
      return tostring(request_table.body(params_map.request_key)) or request_table.params[params_map.request_key].default_value
    elseif request_table.content_type == MULTI then
      if request_table.body(params_map.request_key) ~= nil and request_table.body(params_map.request_key).value~=nil then
        return request_table.body(params_map.request_key).value
      end
      return request_table.params[params_map.request_key].default_value
    end
  end

  if params_map.request_position == "path" then
    return request_table.pathparam[params_map.request_key]
  end

  if params_map.request_position == "constant" then
    return params_map.default_value
  end
end

local function transform_headers(conf,request_table)
  --if conf.filter_type == "0" then
  --  return
  --end
  local changed = false
  local headers
  if conf.filter_type == "1" or conf.filter_type == "0" then
    headers = request_table.header
  end
  if conf.filter_type == "2" then
    for name, _ in pairs(request_table.header) do
      clear_header(name)
    end
    headers = {}
    changed = true
    if conf.default_headers ~= nil and #conf.default_headers > 0 then
      for i = 1, #conf.default_headers do
        headers[conf.default_headers[i]] = request_table.header[conf.default_headers[i]]
      end
    end
  end
  if conf.backend.headers ~= nil or #conf.backend.headers > 0 then
    for _, key, ele in backend_iter(conf.backend.headers) do
    --  key = key:lower()
      headers[key] = getValueFromMapping(ele,request_table)
    end
  end

  --headers.host = nil


  --if conf.backend.content_type ~= nil then
  --  headers[CONTENT_TYPE] = conf.backend.content_type
  --end
  set_headers(headers)
end

local function transform_querystrings(conf,request_table)
  --if conf.filter_type == "0" then
  --  return
  --end
  local changed = flase
  local querystring
  if conf.filter_type == "1" or conf.filter_type == "0" then
    querystring = pl_copy_table(request_table.query)
  end
  if conf.filter_type == "2" then
    querystring = {}
    changed = true
  end
  if conf.backend.querys ~= nil and #conf.backend.querys > 0 then
    for _, key, ele in backend_iter(conf.backend.querys) do
    --  key = key:lower()
      querystring[key] = getValueFromMapping(ele,request_table)
      changed = true
    end
  end
  if changed then
    set_uri_args(querystring)
  end
end

local function transform_json_body(conf, body, content_length,request_table)
  local replaced = false
  local content_length = (body and #body) or 0
  local parameters = {}
  if conf.filter_type == "1" then
    parameters = parse_json(body)
  end

  if conf.backend.bodys ~= nil and #conf.backend.bodys>0 then
    for _, key, ele in backend_iter(conf.backend.bodys) do
    --  key = key:lower()
      parameters[key] = getValueFromMapping(ele,request_table)
      replaced = true
    end
  end

  if replaced then
    return true, cjson.encode(parameters)
  end
end

local function transform_url_encoded_body(conf, request_table)
  if conf.filter_type == "0" then
    return
  end
  local body = get_raw_body()
  local parameters = {}
  if conf.filter_type == "1" then
    parameters = decode_args(body)
  end
  local replaced = false
  if conf.backend.bodys ~= nil and #conf.backend.bodys>0 then
    for _, key, ele in backend_iter(conf.backend.bodys) do
   --   key = key:lower()
      parameters[key] = getValueFromMapping(ele,request_table)
      replaced = true
    end
  end
  if replaced then
    return true, encode_args(parameters)
  end
end

local function transform_multipart_body(conf, request_table)
  --如果为0，则只做透传，不做映射
  if conf.filter_type == "0" then
    return
  end
  local body = get_raw_body()
  local parameters = multipart("", request_table.content_type_value)
  --如果是1，代表位置参数不做过滤，如果是2则进行过滤
  if conf.filter_type == "1" then
    parameters = multipart(body and body or "", request_table.content_type_value)
  end
  local replaced = false
  if conf.backend.bodys ~= nil and #conf.backend.bodys>0 then
    for _, key, ele in backend_iter(conf.backend.bodys) do
    --  key = key:lower()
      parameters:set_simple(key, getValueFromMapping(ele,request_table))
      replaced = true
    end
  end

  if replaced then
    return true, parameters:tostring()
  end
end

local function transform_body(conf,request_table)
  --目前只做form-data类型的body参数转换
  if request_table.content_type ~= MULTI and request_table.content_type ~= ENCODED   then
    return
  end
  if conf.backend.bodys == nil or #conf.backend.bodys < 1 then
    return
  end
  local bodys
  --print_r(request_table.body)
  local is_body_transformed = false
 -- is_body_transformed, request_table.body = transform_multipart_body(conf,request_table,request_table.content_type_value)
  if request_table.content_type == ENCODED then
    is_body_transformed, bodys = transform_url_encoded_body(conf, request_table,request_table.content_type_value)
  elseif request_table.content_type == MULTI then
    is_body_transformed, bodys = transform_multipart_body(conf, request_table,request_table.content_type_value)

  --elseif content_type == JSON then
    --is_body_transformed, body = transform_json_body(conf, body, content_length,request_table)
  end
  if bodys ~= nil then
  end
  if is_body_transformed then
    set_raw_body(bodys)
    set_header(CONTENT_LENGTH, #bodys)
  end
end

local function transform_method(conf,request_table)
  if conf.backend.http_method then
    set_method(conf.backend.http_method:upper())
  end
end

local function transform_uri(conf,request_table)
  local replaced = false
  if conf.backend.uri then
    replaced = true
    local mapping_uri = conf.backend.uri
    if conf.backend.paths ~= nil and #conf.backend.paths>0 then
      for _, key, ele in backend_iter(conf.backend.paths) do
       -- key = key:lower()
        local replacedValue = getValueFromMapping(ele,request_table)
        local pattern = '%['.. key .. ']'
        mapping_uri = gsub(mapping_uri, '%['.. key .. ']', getValueFromMapping(ele,request_table))

      end
    end
    if replaced then
      kong.service.request.set_path(mapping_uri)
    end
  end
end

local function request_check(conf,request_table)
  --校验请求的contentType是否合法
  --if request_table.content_type == nil then
   -- error("[api-transformer] he requestContentType is nil" ..
    --  tostring(conf.request.content_type))
    --return kong.response.error(403, "[api-transformer] the requestContentType is nil" ..
     -- tostring(conf.request.content_type))
  --end
  if conf.filter_type == "0" then
    return
  end
  if conf.filter_type ~= "0" and request_table.content_type ~= conf.request.content_type and (request_table.method:lower() == "post" or request_table.method:lower() =="put" or request_table.method:lower() =="patch") then
    --error("[api-transformer] the requestContentType is valid " ..
    --  tostring(conf.request.content_type))
    return kong.response.error(403, "[api-transformer] the requestContentType is valid" ..
      tostring(conf.request.content_type))
  end

  --校验HTTP方法是否正确
  if conf.request.http_method == nil then
    --error("[api-transformer] the method is nil" ..
    --  tostring(conf.request.http_method))
    return kong.response.error(403, "[api-transformer] the method is nil" ..
      tostring(conf.request.http_method))
  end
  if request_table.method:lower() ~= conf.request.http_method:lower() then
    --error("[api-transformer] the request.http_method is valid " ..
    --  tostring(conf.request.http_method))
    return kong.response.error(403, "[api-transformer] the method is valid" ..
      tostring(conf.request.http_method))
  end

  --获取请求path中的参数值
  request_table.pathparam = path_params(conf.request.uri,request_table.path,conf.request.paths)
  --校验header中的传值是否准确
  if conf.request.headers ~= nil and #conf.request.headers>0 then
    for _, key, ele in request_iter(conf.request.headers) do
      --key = key:lower()
      if ele.not_null == true and request_table.header[key] == nil then
        --error("[api-transformer] the header " .. key .." is null ")
        return kong.response.error(403, "[api-transformer] the header " .. key .." is null ")
      end
      request_table.params[key] = ele
    end
  end
  --校验query中的传值是否准确
  if conf.request.querys ~= nil and #conf.request.querys>0 then
    for _, key, ele in request_iter(conf.request.querys) do
   --   key = key:lower()
      if ele.not_null == true and request_table.query[key] == nil then
        --error("[api-transformer] the querys " .. key .." is null ")
        return kong.response.error(403, "[api-transformer] the querys " .. key .." is null ")
      end
      request_table.params[key] = ele
    end
  end


  --校验body中的传值是否准确
  if conf.request.bodys ~= nil and #conf.request.bodys>0 and request_table.content_type == MULTI  then
    for _, key, ele in request_iter(conf.request.bodys) do
     -- key = key:lower()
      if content_type == ENCODED then
        if ele.not_null == "true" and request_table.bodys[key] == nil then
          --error("[api-transformer] the bodys " .. key .." is null ")
          return kong.response.error(403, "[api-transformer] the bodys " .. key .." is null ")
        end
      elseif content_type == MULTI then
        if ele.not_null == "true" and request_table.bodys:get(key) == nil then
          --error("[api-transformer] the bodys " .. key .." is null ")
          return kong.response.error(403, "[api-transformer] the bodys " .. key .." is null ")
        end
      elseif content_type == JSON then
        if ele.not_null == "true" and request_table.bodys[key] == nil then
          --error("[api-transformer] the bodys " .. key .." is null ")
          return kong.response.error(403, "[api-transformer] the bodys " .. key .." is null ")
        end
      end
      request_table.params[key] = ele
    end
  end


end


function _M.execute(conf)
  local request_table = {
    method = kong.request.get_method(),
    header = kong.request.get_headers(),
    query = get_uri_args() or EMPTY,
    path = kong.request.get_path(),
    body = function(key)
      local rawbody = get_raw_body()
      if get_content_type(get_header(CONTENT_TYPE)) == ENCODED then
        return decode_args(rawbody)[key]
      elseif get_content_type(get_header(CONTENT_TYPE)) == MULTI then
        return multipart(rawbody and rawbody or "", get_header(CONTENT_TYPE)):get(key)
      elseif get_content_type(get_header(CONTENT_TYPE)) == JSON then
        return parse_json(rawbody)[key]
      end
    end,
    content_type_value = get_header(CONTENT_TYPE),
    content_type = get_content_type(get_header(CONTENT_TYPE)),
    params = {},
  }
  request_check(conf,request_table)
  transform_uri(conf,request_table)
  transform_method(conf,request_table)
  transform_headers(conf,request_table)
  transform_body(conf,request_table)
  transform_querystrings(conf,request_table)
end

return _M
