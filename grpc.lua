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
local pcall         = pcall
local decode_base64 = ngx.decode_base64

local lpack = require "lua_pack"
local protoc = require "protoc"
local pb = require "pb"
local pl_path = require "pl.path"
local date = require "date"

local bpack = lpack.pack
local bunpack = lpack.unpack


local grpc = {}


local function safe_set_type_hook(type, dec, enc)
  if not pcall(pb.hook, type) then
    ngx.log(ngx.NOTICE, "no type '" .. type .. "' defined")
    return
  end

  if not pb.hook(type) then
    pb.hook(type, dec)
  end

  if not pb.encode_hook(type) then
    pb.encode_hook(type, enc)
  end
end

local function set_hooks()
  pb.option("enable_hooks")
  local epoch = date.epoch()

  safe_set_type_hook(
    ".google.protobuf.Timestamp",
    function (t)
      if type(t) ~= "table" then
        error(string.format("expected table, got (%s)%q", type(t), tostring(t)))
      end

      return date(t.seconds):fmt("${iso}")
    end,
    function (t)
      if type(t) ~= "string" then
        error (string.format("expected time string, got (%s)%q", type(t), tostring(t)))
      end

      local ds = date(t) - epoch
      return {
        seconds = ds:spanseconds(),
        nanos = ds:getticks() * 1000,
      }
    end)
end

--- loads a .proto file optionally applies a function on each defined method.
function grpc.each_method(fname, f, recurse,flag)
  local dir = pl_path.splitpath(pl_path.abspath(fname))
  local parsed
  if flag then
    local p = protoc.new()
    p:addpath("/usr/include")
    p:addpath("/usr/local/opt/protobuf/include/")
    p:addpath("/usr/local/kong/lib/")
    p:addpath("kong")
    p:addpath("kong/include")
    p:addpath("spec/fixtures/grpc")

    p.include_imports = true
    p:addpath(dir)
    p:loadfile(fname)
    set_hooks()
    parsed = p:parsefile(fname)
    if f then

      if recurse and parsed.dependency then
        if parsed.public_dependency then
          for _, dependency_index in ipairs(parsed.public_dependency) do
            local sub = parsed.dependency[dependency_index + 1]
            grpc.each_method(sub, f, true,true)
          end
        end
      end

      for _, srvc in ipairs(parsed.service or {}) do
        for _, mthd in ipairs(srvc.method or {}) do
          f(parsed, srvc, mthd)
        end
      end
    end

    return parsed
  else
    local content = [[syntax = "proto2";
 option java_multiple_files = true;
package io.github.hundanli.grpc.greeter.hello;
service HelloService {
 rpc hola(HelloRequest) returns (HelloResponse){
 option (google.api.http) = {
 get: "/demo/v1/messages/{name}"
 };
 }
}
message HelloRequest {
 required string name = 1;
}
message HelloResponse {
 required string message = 1;
}]]
    parsed =  grpc.compile_proto(content)
    --parsed = parsed["testsss"]
    local parsed2 = parsed["testsss"]
    parsed2.pb_state=parsed.pb_state
    if f then

      if recurse and parsed.dependency then
        if parsed.public_dependency then
          for _, dependency_index in ipairs(parsed.public_dependency) do
            local sub = parsed.dependency[dependency_index + 1]
            grpc.each_method(sub, f, true,false)
          end
        end
      end
      for _, srvc in ipairs(parsed2.service or {}) do
        for _, mthd in ipairs(srvc.method or {}) do
          f(parsed2, srvc, mthd)
        end
      end
    end

    return parsed2
  end

  local proto_fake_file = "filename for loaded"
  --protoc.reload()


end


function grpc.compile_proto(content)
  -- clear pb state
  local old_pb_state = pb.state(nil)

  local compiled, err = grpc.compile_proto_text(content)
  if not compiled then
    compiled = grpc.compile_proto_bin(content)
    if not compiled then
      return nil, err
    end
  end

  -- fetch pb state
  compiled.pb_state = pb.state(old_pb_state)
  return compiled
end

function grpc.compile_proto_text(content)
  protoc.reload()
  local _p  = protoc.new()
  -- the loaded proto won't appears in _p.loaded without a file name after lua-protobuf=0.3.2,
  -- which means _p.loaded after _p:load(content) is always empty, so we can pass a fake file
  -- name to keep the code below unchanged, or we can create our own load function with returning
  -- the loaded DescriptorProto table additionally, see more details in
  -- https://github.com/apache/apisix/pull/4368
  local ok, res = pcall(_p.load, _p, content, "testsss")
  if not ok then
    return nil, res
  end

  if not res or not _p.loaded then
    return nil, "failed to load proto content"
  end

  local compiled = _p.loaded
  return compiled
end

function grpc.compile_proto_bin(content)
  content = decode_base64(content)
  if not content then
    return nil
  end

  -- pb.load doesn't return err
  local ok = pb.load(content)
  if not ok then
    return nil
  end

  local files = pb.decode("google.protobuf.FileDescriptorSet", content).file
  local index = {}
  for _, f in ipairs(files) do
    for _, s in ipairs(f.service or {}) do
      local method_index = {}
      for _, m in ipairs(s.method) do
        method_index[m.name] = m
      end

      index[f.package .. '.' .. s.name] = method_index
    end
  end

  local compiled = {}
  compiled["testsss"] = {}
  compiled["testsss"].index = index
  return compiled
end


--- wraps a binary payload into a grpc stream frame.
function grpc.frame(ftype, msg)
  return bpack("C>I", ftype, #msg) .. msg
end

--- unwraps one frame from a grpc stream.
--- If success, returns `content, rest`.
--- If heading frame isn't complete, returns `nil, body`,
--- try again with more data.
function grpc.unframe(body)
  if not body or #body <= 5 then
    return nil, body
  end

  local pos, ftype, sz = bunpack(body, "C>I")       -- luacheck: ignore ftype
  local frame_end = pos + sz - 1
  if frame_end > #body then
    return nil, body
  end

  return body:sub(pos, frame_end), body:sub(frame_end + 1)
end



return grpc
