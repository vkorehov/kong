local Errors = require "kong.dao.errors"
local utils = require "kong.tools.utils"
local http = require "resty.http"
local cjson = require "cjson"
local kill = require "kong.cmd.utils.kill"
local http_client = require "httpclient"
local luatz = require "luatz"
local pl_string = require "pl.stringx"
local uuid = utils.uuid

-- enable or disable logging
local TTL_CLEANUP_INTERVAL = 60 -- 1 minute
local _M = require("kong.dao.db").new_db("consul")
local ngx_stub = _G.ngx


function _M:init_worker()
  self:start_ttl_timer()
  return true
end

_M.dao_insert_values = {
  id = function()
    return uuid()
  end,
  _id = function()
    return id
  end
}


-- during init checks consul status
function _M.new(kong_config)  
  local self = _M.super.new()
  self.query_options = {
    host = kong_config.consul_host,
    port = kong_config.consul_port,
    key_root = kong_config.consul_key_root,
    connection_timeout = kong_config.consul_connection_timeout,
    version = kong_config.consul_version,
    protocol = kong_config.consul_protocol
  }
  
  local status_check_path = self.query_options.version.."/status/leader";
  local res,err = self.lusis_http_client_call(self,status_check_path,"GET")
  if not res then
    ngx.log(ngx.ERR, "[consul] could not get consul status: "..tostring(err))
    print("[consul] could not get consul status: "..tostring(err))
    error(tostring(err))
  end

  return self
end

-- used by kong
function _M:infos()
  return {
    desc = "database",
    name = self:clone_query_options().key_root
  }
end



--returns consul key value database root key
local function get_key_root(self)
  return "/"..self:clone_query_options().version.."/kv/"..self:clone_query_options().key_root
end

--returns consul key value database version key
local function get_key_root_version(self)
  return "/"..self:clone_query_options().version.."/kv/"
end

--checks for composite key, schema who have multiple primary keys
local function is_composite_key(schema,model)
  local primaryKeys = schema.primary_key;
  
  if #primaryKeys == 0 or primaryKeys == nil then return false end
  
  for _,key_name in pairs(primaryKeys) do 
    local key_value = model[key_name]
    if key_value==nil then return false end
  end
  
  return true
end

-- from shema returns fk keys
local function get_fk_paths(schema,model,key_name)
  local res = {}
  if schema == nil then return res end
  if model == nil then model = {} end
  local fields = schema.fields
  local primaryKeys = schema.primary_key
  
  if primaryKeys==nil or next(primaryKeys) == nil then return res end
  if fields==nil or next(fields)==nil then return res end
  
  for _,pk_name in pairs(primaryKeys) do
    local pk_value = model[pk_name]
    if pk_value==nil then pk_value="" end
    
    for field_name,value_table in pairs(fields) do 
      if 'table'==type(value_table) then
         if value_table.foreign ~= nil then
             local fk_key_value = model[field_name]
             if fk_key_value ~= nil and 'string'==type(fk_key_value) and #fk_key_value>0 then
                local splitRes =utils.split(value_table.foreign, ":")
                table.insert(res,splitRes[1].."/"..splitRes[2].."/"..fk_key_value.."/"..key_name.."/"..pk_name.."/"..pk_value)
             end
         end
      end
    end 
  end
  return res
end

-- from shema return unique field keys
local function get_unique_field_paths(schema,model,key_name)
  local res = {}
  if schema == nil then return res end
  if model == nil then model = {} end
  local fields = schema.fields
  local primaryKeys = schema.primary_key
  
  if primaryKeys==nil or next(primaryKeys) == nil then return res end
  if fields==nil or next(fields)==nil then return res end
  
  for _,pk_name in pairs(primaryKeys) do
    local pk_value = model[pk_name]
    if pk_value==nil then pk_value="" end
    
    for field_name,value_table in pairs(fields) do 
      if 'table'==type(value_table) then
         if value_table.unique ~= nil and value_table.unique == true then
             
             local unique_key_value = model[field_name]
             if unique_key_value ~= nil and 'string'==type(unique_key_value) and #unique_key_value>0 then
                table.insert(res,key_name.."/"..field_name.."/"..unique_key_value)
             end
         end
      end
    end 
  end
  return res
end

-- returns pk paths + composite pk path in table type
local function get_all_pks(schema,model,key_name)
  local composite_key = ""
  local composite_key_value = ""
  local res = {}
  if model==nil then model={} end
  local primaryKeys = schema.primary_key;
  if #primaryKeys == 0 then return res end
  
  if #primaryKeys >1 then
    local primaryKeysFiltered = {}
    for i, pk in pairs(primaryKeys) do
      if pk == 'id' then
        table.insert(primaryKeysFiltered,pk)
      end
    end 
    primaryKeys = primaryKeysFiltered
    if #primaryKeys == 0 then
      ngx.log(ngx.ERR, "[consul] for key "..key_name.." can not build trustfull key from primary keys")
    end
  end
  
  
  for _,pk_key_name in pairs(primaryKeys) do 
    local pk_key_value = model[pk_key_name]
    if pk_key_value==nil then pk_key_value="" end
    
    if type(pk_key_value)=='string' and #pk_key_value >0 then
      local key_path = pk_key_name.."/"..pk_key_value
      composite_key = composite_key..pk_key_name
      composite_key_value = composite_key_value..pk_key_value
      if key_name ~= nil then
        key_path = key_name.."/"..key_path
      end
      local pk = res.pk
      if pk == nil then
        pk = {}
        res.pk = pk
      end
      table.insert(pk,key_path)
    end
  end
  
  if #composite_key>0 then
    composite_key = "composite/"..composite_key.."/"..composite_key_value
  else
    composite_key=""
  end
  
  if key_name ~= nil and #composite_key>0 then
      composite_key = key_name.."/"..composite_key
  end
  
  if #composite_key>0 then
    --table.insert(res,composite_key)
    res.composite_key = composite_key
  end 
  return res
end


-- returns only composite pk
local function get_composit_pk_path(schema,model,key_name)
  local all_pk = get_all_pks(schema,model,key_name) 
  if all_pk == nil then return {} end 
  return all_pk.composite_key
end

-- return only pk paths without composite path
local function get_only_pk_paths(schema,model,key_name)
  local all_pk = get_all_pks(schema,model,key_name) 
  if all_pk == nil then return {} end 
  if all_pk.pk == nil then return {} end
  return all_pk.pk
end

-- return all pk paths and composite as well
local function get_pk_paths(schema,model,key_name)
  local all_pk = get_all_pks(schema,model,key_name) 
  if all_pk == nil then return {} end 
  local res = all_pk.pk
  if res == nil then res={} end
  if all_pk.composite_key ~= nil then table.insert(res,all_pk.composite_key) end
  return res
end

-- builds key path
local function get_key_path(key_table)
  local key_path = ""
  table.sort(key_table)
  local i = 0
  for key,value in pairs(key_table) do 
    if type(value)=='string' and #value >0 then
      if i>0 then
        key_path = key_path.."/"      
      end
      key_path = key_path..key.."/"..value
      i = i+1
    end
  end
  return key_path
end

-- based on key_name=key_value table and root key name builds key path list
local function get_key_paths(key_table,key_name)
  local key_paths = {}
  table.sort(key_table)
  -- creates composite key and also individual ones
  local root_key_path = ""
  local i = 0
  
  for key,value in pairs(key_table) do 
    if type(value)=='string' and #value >0 then
      local key_path=key.."/"..value
      if(key_name ~= nil) then
        key_path = key_name.."/"..key_path
      end
      table.insert(key_paths,key_path)
      if i>0 then
        root_key_path = root_key_path.."/"      
      end
      root_key_path = root_key_path..key.."/"..value
      i = i+1
    end
  end
  
  if table[root_key_path] == nil then
    --table.insert(key_paths,root_key_path)
  end
  return key_paths
end

--[[
local function get_http_client(premature)
  local client = http.new()
  client:set_timeout(self:clone_query_options().connection_timeout)
  return client
end
--]]

-- converts lua object to json
local function convert_to_json_string(data)
  if data == nil then
    return "";
  end
  local jsonString,err = cjson.encode(data)
  if err ~= nil then
    ngx.log(ngx.ERR, "[consul] failed to convert to JSON string "..tostring(err))
  end
  return jsonString,err
end

--converts from json to lua object
local function convert_from_json_string(json_string)
  if json_string == nil then
    return {}
  end
  
  local lua_data,err = cjson.decode(json_string)
  if err ~= nil then
    ngx.log(ngx.ERR, "[consul] failed to convert from JSON string "..tostring(err))
  end
  if lua_data == nil then 
    lua_data={}
  end
  return lua_data,err
end

-- converts to lua object and extracts BASE64 encoded vale from consul key
local function convert_and_extract(json_string)
  local results = {}
  local res, err = convert_from_json_string(json_string)
  if err ~= nil then
    ngx.log(ngx.ERR, "[consul] failed to convert from JSON string "..tostring(err))
    error({code=001,message="Failed to convert and extract data from Consul response"})
  end
  if 'table' == type(res) then
    for key,value in pairs(res) do 
      local base64Value = value['Value'];
      
      if base64Value ~= nil then
        local valueString = ngx.decode_base64(base64Value)
        local resValue, err = convert_from_json_string(valueString)
        if err ~= nil then
          ngx.log(ngx.ERR, "[consul] failed decode value from valueJsonString "..tostring(err))
        end
        table.insert(results,resValue)
      end
    end
  end
  return results;
end


-- used for development to trace 
local function trace(message, data) 
  local dev_log = require "kong.cmd.utils.nlog"
  dev_log.printc(message,data)
end


-- lusis http client
function _M:lusis_http_client_call(consul_key, method, body)
  local hc = http_client.new()
  local address = self:clone_query_options().protocol..'://'..self:clone_query_options().host..":"..self:clone_query_options().port
  local result_body = nil
  local res, err = nil 
  if method == 'GET' then
    res, err = hc:get(address.."/"..consul_key)
  elseif method == 'PUT' then
    res, err = hc:put(address.."/"..consul_key,body)  
  elseif method == 'DELETE' then
    res, err = hc:delete(address.."/"..consul_key)  
  end
  if err~=nil then
     return res,err
  end
  
  if res==nil then
    return nil,"[consul] http result is nil "..consul_key.." method "..method
  end
  
  if res.err ~= nil and #res.err>0 then
    return nil,res.err
  end
  
  if res.code == 200 then
    result_body = res.body
    ngx.log(ngx.INFO, "[consul] status 200 ok for key: "..consul_key.." method "..method)
  elseif res.code >= 400 and res.code < 500 and res.code~=404 then
    ngx.log(ngx.ERR, "[consul] not ok response code: "..res.code.." error details "..tostring(err))
  elseif res.code >= 500 then
    ngx.log(ngx.ERR, "[consul] not ok response code: "..res.code.." error details "..tostring(err))
  end
  return result_body, err
end

--[[
function _M:resty_http_client_call(consul_key, method, body)
  local client = get_http_client()
  local ok, err = client:connect(self:clone_query_options().host, self:clone_query_options().port)
  local result_body = nil
  if not ok then
    ngx.log(ngx.ERR, "[consul] could not connect to consul: "..tostring(err))
  else
    local res, err =  client:request {
              method = method,
              path = consul_key,
              body = body,
              headers = {
                ["Content-Type"] = "application/json",
              }
    }
    if not res then
      ngx.log(ngx.ERR, "[consul] could not connect to consul: "..tostring(err))
    else
      local body = "" 
      if res.status == 200 then
        result_body = res:read_body()
        ngx.log(ngx.INFO, "[consul] status 200 ok for key: "..consul_key.." method "..method)
      elseif res.status >= 400 and res.status < 500 and res.status~=404 then
        ngx.log(ngx.ERR, "[consul] not ok response code: "..res.status.." error details "..tostring(err))
      elseif res.status >= 500 then
        ngx.log(ngx.ERR, "[consul] not ok response code: "..res.status.." error details "..tostring(err))
      end
    end
  end
  return result_body, err
end
--]]


--[[
  
   !!! FOR PLUGINS DIFFERENT HTTP CLIENT IS USED SINCE THEY ARE REQUESTED DURING INIT PHASE RESTY
  
   /usr/local/kong/luarocks/share/lua/5.1/kong/cmd/start.lua:21: nginx: [error] init_by_lua error: /usr/local/kong/luarocks/share/lua/5.1/resty/http.lua:90: no request found
   stack traceback:
        [C]: in function 'ngx_socket_tcp'
        /usr/local/kong/luarocks/share/lua/5.1/resty/http.lua:90: in function 'new'
        ...local/kong/luarocks/share/lua/5.1/kong/dao/consul_db.lua:67: in function 'get_http_client'
        ...local/kong/luarocks/share/lua/5.1/kong/dao/consul_db.lua:140: in function 'http_call'
        ...local/kong/luarocks/share/lua/5.1/kong/dao/consul_db.lua:331: in function 'find_all'
        /usr/local/kong/luarocks/share/lua/5.1/kong/dao/dao.lua:170: in function 'find_all'
        /usr/local/kong/luarocks/share/lua/5.1/kong.lua:55: in function 'load_plugins'
        /usr/local/kong/luarocks/share/lua/5.1/kong.lua:132: in function 'init'
        init_by_lua:4: in main chunk
  
  !!! ngx.socket.tcp is not available at the init or init_worker phases !!!
  --]]
  
--lusis http client wrapper  
function _M:http_call(consul_key, method, body)
  local result_body,err = self:lusis_http_client_call(consul_key,method,body)
  return result_body,err
end


-- adds record in schema_migrations collection
function _M:record_migration(id, name)
  -- not used
end

-- No mmigrations are run
function _M:current_migrations()
  --not used
  return {}
end


function _M:insert(key_name, schema, model, constraints, options)
   trace("insert "..key_name,model)
  -- obtains all key kombinations for entity
  local pk_paths = get_pk_paths(schema, model,key_name)
  local fk_paths = get_fk_paths(schema,model,key_name)
  local unique_key_paths = get_unique_field_paths(schema,model,key_name)
  
  local key_paths = {}
  for k,v in pairs(pk_paths) do table.insert(key_paths,v) end
  for k,v in pairs(fk_paths) do table.insert(key_paths,v) end
  for k,v in pairs(unique_key_paths) do table.insert(key_paths,v) end
  
  local key_root = get_key_root(self)
  
  model.created_at=math.floor(luatz.gettime.gettime())*1000 -- sec*1000=milisec
  
  local modeljson = convert_to_json_string(model)
  
  --consider to execute multiple put operations in single consul transaction
  for i, key_path in pairs(key_paths) do
    local consul_key = key_root.."/"..key_path
    local body,err = self:http_call(consul_key,"PUT",modeljson)

    if err then
      ngx.log(ngx.ERR, "[consul] failed to insert value. Error details "..tostring(err))
      return nil, err
    end
  end
    
  if options and options.ttl then
    local _, err = self:ttl(key_name, schema, model, constraints, options,key_paths)
    if err then
      ngx.log(ngx.ERR, "[consul] failed to insert in ttl. Error details "..tostring(err))
    end
  end  
        
  return model
end

-- some entities as oauth2 token have ttl, this is used to cleanup key spaces once 
-- token is not valid anymore
function _M:ttl(key_name, schema, model, constraints, options,key_paths)
    local ttl = options.ttl 
    -- init timer
    --self:start_ttl_timer()
    if model == nil then model = {} end
    if constraints == nil then constraints = {} end
    if schema == nil then schema = {} end
    
    
    if not schema.primary_key or #schema.primary_key ~= 1 then
      return false, "Cannot set a TTL if the entity has no primary key, or has more than one primary key"
    end
    
    local expire_at = math.floor(luatz.time())+ttl -- seconds
    local et = luatz.timetable.new_from_timestamp(expire_at)
    
    local primary_key_table = schema.primary_key
    local primary_key = primary_key_table[1]
    local primary_key_value = model[primary_key]
    local primary_uui_value = primary_key_value
    
    local ttl_model={}
    ttl_model['primary_key_name'] = primary_key
    ttl_model['primary_key_value'] = primary_key_value
    ttl_model['primary_uuid_value'] = primary_uui_value
    ttl_model['key_name'] = key_name
    ttl_model['expire_at'] = expire_at
    ttl_model['created_at']= math.floor(luatz.time())
    ttl_model['key_paths'] = key_paths

    local ttl_key = get_ttl_key(model, key_name, schema, ttl)
    local ttl_insert_key = ttl_key.."/"..et.day.."_"..et.month.."_"..et.year.."_"..et.hour.."_"..et.min
    
    if ttl_key~=nil then
      local key_root = get_key_root(self)
      local find_key = key_root.."/"..ttl_key.."?recurse&keys"
      
      --look for existing keys
      local body,err = self:http_call(find_key,"GET")    
      
      if err~=nil then
        ngx.log(ngx.ERR, "[consul] ttl find key error for key: "..find_key.." -> "..tostring(err)) 
        return nil 
      end
      
      if body ~= nil then 
        -- just delete whatever is there
        local body_json,err = cjson.decode(body)
        if err then
          ngx.log(ngx.ERR, "[consul] failed to deserialize ttl key "..tostring(err))
          return nil, err
        end
        
        for _,key in pairs(body_json) do 
          local to_delete_key = get_key_root_version(self)..key
          local body,err = self:http_call(to_delete_key,"DELETE","")
          if err then
            ngx.log(ngx.ERR, "[consul] failed to delete ttl. Error details "..key.."->"..tostring(err))
            return nil, err
          end
        end
      end
      --inserts new ttl model
      local modeljson = convert_to_json_string(ttl_model)
      local consul_key = key_root.."/"..ttl_insert_key
      local body,err = self:http_call(consul_key,"PUT",modeljson)
      if err then
        ngx.log(ngx.ERR, "[consul] failed to insert ttl value. Error details "..tostring(err))
        return nil, err
      end
    end    
  return true
end

-- TTL clean up timer functions

local function do_clean_ttl(premature, mon)
   if premature then return end
   mon:clear_expired_ttl()
   local ok, err = ngx.timer.at(TTL_CLEANUP_INTERVAL, do_clean_ttl, mon)
   if not ok then
    ngx.log(ngx.ERR, "failed to create timer: ", err)
   end
end


function _M:start_ttl_timer()
  if ngx and self.timer_started==nil then
    local ok, err = ngx.timer.at(TTL_CLEANUP_INTERVAL, do_clean_ttl, self)
     if not ok then
         ngx.log(ngx.ERR, "failed to create the timer: ", err)
         return
     end
    self.timer_started = true
    trace("start_ttl_timer[timer_started] --->",self.timer_started)
  end
end

function get_ttl_key(model, key_name, schema, ttl)
    local ttl_helper = {}
    local primary_key_table = schema.primary_key
    local primary_key = primary_key_table[1]
    local primary_key_value = model[primary_key]
    local primary_uui_value = primary_key_value
    
    return "ttls/"..key_name.."/"..primary_key.."/"..primary_key_value
end


local function get_timezone(now)
  return os.difftime(now, os.time(os.date("!*t", now)))
end

function _M:clear_expired_ttl()

  local key_root = get_key_root(self)
  local key_version = get_key_root_version(self)
  local quer_all_keys = key_root.."/ttls/?keys"
  --look for existing keys
  local body,err = self:http_call(quer_all_keys,"GET") 
  
  if err~=nil then
    ngx.log(ngx.ERR, "[consul] ttl find key error for key: "..find_key) 
    return nil 
  end
  
  if body == nil then 
    return nil
  end
  
  local body_json,err = cjson.decode(body)
  if err then
    ngx.log(ngx.ERR, "[consul] failed to deserialize ttl key "..tostring(err))
    return nil, err
  end
  
  for _,key in pairs(body_json) do 
    local tokenized_key = pl_string.split(key,"/")
    if tokenized_key ~=nil then
      local now = math.floor(luatz.time()) -- seconds
     
      local ts_part = tokenized_key[#tokenized_key]
      local tokenized_ts_part = pl_string.split(ts_part,"_")
      local year = tokenized_ts_part[3]
      local month = tokenized_ts_part[2]
      local day = tokenized_ts_part[1]
      local hour = tokenized_ts_part[4]
      local min = tokenized_ts_part[5]
      local sec = 59
      local expire_at = os.time{year=year, month=month, day=day, hour=hour,min=min,sec=sec}  --seconds
      
      --compensate timezone difference
      expire_at = expire_at + get_timezone(now)
      if now > expire_at then
        local to_clean_up_key = key_version..key
        local res,err = self:find_by_key(to_clean_up_key)
        if err then
          ngx.log(ngx.ERR, "[consul] failed cleanup ttl key "..to_clean_up_key.." -> "..tostring(err))
          return nil, err
        end
        if res then
          
          --delete ttl linked entity keys
          for _,delet_key_path in pairs(res.key_paths) do 
             delet_key_path = key_root.."/"..delet_key_path
             -- implement delete by key function
             local body,err = self:http_call(delet_key_path,"DELETE","")
             if err then
               ngx.log(ngx.ERR, "[consul] failed to delete ttl linked entity key_path . Error details "..delet_key_path.."->"..tostring(err))
               return nil, err
             end  
              
          end
          
          local body,err = self:http_call(to_clean_up_key,"DELETE","")
          if err then
            ngx.log(ngx.ERR, "[consul] failed to delete ttl in cleanup process. Error details "..key.."->"..tostring(err))
            return nil, err
          end  
        end
      end
    end
  end

  return true
end



function _M:find(key_name, schema, filter)
  trace("find "..key_name,filter) 
  local result,err = self:find_all(key_name, filter, schema)
  if err ~= nil then
    ngx.log(ngx.ERR, "[consul] find error for key root: "..key_name)  
  end
  if result==nil or #result==0 then return result,nil end
  return result[1];
  
end



function _M:find_by_key(key_path)
  trace("find_by_key",key_path)
  local body,err = self:http_call(key_path,"GET")
  if(body==nil)then return{} end
  if err ~= nil then
    ngx.log(ngx.ERR, "[consul] find_by_key error for key: "..key_path)  
  end
  local result=convert_and_extract(body)
  if result==nil or #result==0 then return result,nil end
  return result[1];
end




function _M:count(key_name, filter, schema)
  local count=0
  if filter == nil then filter = {} end
  local key_root =  get_key_root(self)
  
  local composite_key_path = get_composit_pk_path(schema, filter,key_name)
  local consul_key = composite_key_path
  if composite_key_path == nil then
    
    local pk_paths = get_pk_paths(schema, filter,key_name)
    if next(pk_paths) ~= nil then
      for index,key_path in pairs(pk_paths) do 
        consul_key = key_root.."/"..key_path
      end  
    end
    
    if consul_key == nil then
      local fk_paths = get_fk_paths(schema,filter,key_name)
      for index,key_path in pairs(fk_paths) do 
        consul_key = key_root.."/"..key_path
      end
    end
    
    if consul_key == nil then
      local unique_key_paths = get_unique_field_paths(schema,filter,key_name)
      for index,key_path in pairs(unique_key_paths) do 
        consul_key = key_root.."/"..key_path
      end
    end
  
  else
    consul_key = key_root.."/"..consul_key
  end
  
  
  if consul_key == nil then 
    consul_key = key_root.."/"..key_name.."/composite"
  end 
  
  consul_key = consul_key.."?recurse&keys"
   
  local body = nil
  local body,err = self:http_call(consul_key,"GET")    
  if err~=nil then
    ngx.log(ngx.ERR, "[consul] count error for key: "..consul_key..tostring(err))  
  end
  if body ~= nil then
    local body_json = cjson.decode(body)
    count = #body_json
  end
  return count
end

function _M:update(key_name, schema, constraints, filter, values, nils, full, model, options)
  local res,err = self:insert(key_name, schema, model, constraints, options)
  if err~=nil then
     ngx.log(ngx.ERR, "[consul] failed to update value. Error details "..tostring(err))
  end
  return self:find(key_name, schema, filter)
end

function get_associated_entites(constraints,model)
  -- Find associated entities
  local associated_entites = {}
    if constraints ~= nil and constraints.cascade ~= nil then
      for f_entity, cascade in pairs(constraints.cascade) do
        local f_fetch_keys = {[cascade.f_col] = model[cascade.col]}
        associated_entites[cascade.table] = {
          schema = cascade.schema,
          filter = f_fetch_keys
        }
      end
    end
  return associated_entites;
end

-- returns linked entities key paths.
-- Example: Once Consumer is deleted all related Keys and Oauth2 clients also need to be cleaned up
function get_associated_key_paths(constraints,model)
  local associated_key_paths = {}
  if constraints ~= nil and constraints.cascade ~= nil then
    for f_entity, cascade in pairs(constraints.cascade) do
      local f_fetch_keys = {[cascade.f_col] = model[cascade.col]}
      local fk_table = {}--get_fk_and_values(cascade.schema,f_fetch_keys)
      local fk_key_paths = get_key_paths(fk_table)
      for k,v in pairs(fk_key_paths) do 
        local key_path = cascade.table.."/"..v
        
        table.insert(associated_key_paths,{
          table = cascade.table,
          key_path = key_path,
          schema = cascade.schema,
          filter = f_fetch_keys 
        })
      end
    end
  end
  return associated_key_paths;
end

function _M:delete(key_name, schema, filter, constraints)
  trace("delete "..key_name,filter)
  local key_root = get_key_root(self)
  local to_delete_rows  = self:find_all(key_name, filter, schema)
  if to_delete_rows == nil or #to_delete_rows==0 then
    ngx.log(ngx.ERR, "[consul] nothing to delete for key")
    return {}
  end
  
  if(constraints ~= nil) then
    local associated_entities = get_associated_entites(constraints,filter)
    
    for linked_entity_name,value_obj in pairs(associated_entities) do 
      self:delete(linked_entity_name,value_obj.schema,value_obj.filter)
    end
  end
  
  
  local to_delete = to_delete_rows[1]
  local pk_paths = get_pk_paths(schema, to_delete,key_name)
  local fk_paths = get_fk_paths(schema,to_delete,key_name)
  local unique_key_paths = get_unique_field_paths(schema,to_delete,key_name)
  
  local key_paths = {}
  for k,v in pairs(pk_paths) do table.insert(key_paths,v) end
  for k,v in pairs(fk_paths) do table.insert(key_paths,v) end
  for k,v in pairs(unique_key_paths) do table.insert(key_paths,v) end
  
  
  --consider to execute multiple put operations in single consul transaction
  for i, key_path in pairs(key_paths) do
      local consul_key = key_root.."/"..key_path.."?recurse"
      local body,err = self:http_call(consul_key,"DELETE","")
      if err then
        ngx.log(ngx.ERR, "[consul] failed to delete for key"..consul_key..". Error details "..tostring(err))
      end
  end
  return to_delete
end

function _M:query(filter, schema)
  trace("query ",filter)
  if filter == nil then filter = {} end
  local key_name = nil
  if scheam ~= nil then
    key_name = schema.table
  end
  if key_name == nil then return {} end
  
  local result,err = self:find_all(key_name, filter, schema)
  if err ~= nil then
    ngx.log(ngx.ERR, "[consul] find error for key root: "..key_name)  
  end
  if result==nil or #result==0 then return result,nil end
  return result;
end


function shallowcopy(orig)
    local orig_type = type(orig)
    local copy = {} 
    if orig_type == 'table' then
        copy = {}
        for orig_key, orig_value in pairs(orig) do
            copy[orig_key] = orig_value
        end
    else -- number, string, boolean, etc
        copy = orig
    end
    return copy
end


function aplyFilter(results,filter,schema)
  local res = {}
  local filter_ref = shallowcopy(filter)
  
  for index1,result in pairs(results) do
    filter_ref = shallowcopy(filter)
    for filter_key,filter_value in pairs(filter_ref) do 
      local res_val = result[filter_key]   
      if res_val~=nil then
        if(res_val==filter_value) then
          filter_ref[filter_key]=nil
        end      
      end
    end
    if next(filter_ref) == nil then
      table.insert(res,result)
    end
  end
  
  return res  
end

function _M:find_page(key_name, filter, page, page_size, schema)
  trace("find_page "..key_name,filter)
  local key_root =  get_key_root(self)
  if filter == nil then filter = {} end
  local is_composite_key = is_composite_key(schema,filter);
  local composite_key_path = nil
  if is_composite_key then
     composite_key_path = get_composit_pk_path(schema, filter,key_name)
  end
  local consul_key = composite_key_path
  
  if composite_key_path == nil then
    
    local pk_paths = get_pk_paths(schema, filter,key_name)
    if next(pk_paths) ~= nil then
      for index,key_path in pairs(pk_paths) do 
        consul_key = key_root.."/"..key_path
      end  
    end
    
    if consul_key == nil then
      local fk_paths = get_fk_paths(schema,filter,key_name)
      for index,key_path in pairs(fk_paths) do 
        consul_key = key_root.."/"..key_path
      end
    end
    
    if consul_key == nil then
      local unique_key_paths = get_unique_field_paths(schema,filter,key_name)
      for index,key_path in pairs(unique_key_paths) do 
        consul_key = key_root.."/"..key_path
      end
    end
    
    
  else
    consul_key = key_root.."/"..consul_key
  end
  
  if consul_key == nil then 
    consul_key = key_root.."/"..key_name.."/composite"
  end 
  
  if page == nil then
    page = 1
  end
  
  --local total_count, err = self:count(key_name, filter, schema)
  --if err then
  --  return nil, err
  --end
  
  
  --local total_pages = math.ceil(total_count/page_size)
  local offset = page_size * (page - 1)
  
  consul_key = consul_key.."?recurse"
  
  local body,err = self:http_call(consul_key,"GET")
  
  if(body==nil)then return{} end
  
  if err ~= nil then
    ngx.log(ngx.ERR, "[consul] finda_page error for key: "..consul_key)  
  end
  
  local rows = convert_and_extract(body)
  rows = aplyFilter(rows,filter,schema)
  local total_count = #rows
  local total_pages = math.ceil(total_count/page_size)
  local page_rows = {}
  local c_start = page_size*(page-1)
  local c_end = c_start+page_size
  if c_end > total_count then
    c_end = total_count
  end 
  if c_start > total_count then
    c_start = total_count
  end
  local c = 0
  for _,row in pairs(rows) do 
    if c >=c_start and c<c_end then
      table.insert(page_rows,row)   
    end  
    c = c+1
  end 
 
  
  
  
  local next_page = page + 1
  return page_rows, nil, (next_page <= total_pages and next_page or nil)
end




function _M:find_all(key_name, filter, schema)
  trace("find_all "..key_name,filter)
  local key_root =  get_key_root(self)
  if filter == nil then filter = {} end
  local is_composite_key = is_composite_key(schema,filter);
  local composite_key_path = nil
  if is_composite_key then
     composite_key_path = get_composit_pk_path(schema, filter,key_name)
  end
  local consul_key = composite_key_path
  
  
  
  if composite_key_path == nil then
    local pk_paths = get_only_pk_paths(schema, filter,key_name)
    if next(pk_paths) ~= nil then
      for index,key_path in pairs(pk_paths) do 
        consul_key = key_root.."/"..key_path
      end  
    end
    
    if consul_key == nil then
      local fk_paths = get_fk_paths(schema,filter,key_name)
      for index,key_path in pairs(fk_paths) do 
        consul_key = key_root.."/"..key_path
      end
    end
    
    if consul_key == nil then
      local unique_key_paths = get_unique_field_paths(schema,filter,key_name)
      for index,key_path in pairs(unique_key_paths) do 
        consul_key = key_root.."/"..key_path
      end
    end
    
    
  else
    consul_key = key_root.."/"..consul_key
  end
  
  if consul_key == nil then 
    consul_key = key_root.."/"..key_name.."/composite"
  end 
  
  consul_key = consul_key.."?recurse"
   
  local body,err = self:http_call(consul_key,"GET")
  if(body==nil)then return{} end
  
  if err ~= nil then
    ngx.log(ngx.ERR, "[consul] finda_all error for key: "..consul_key)  
  end
  
  local rows = convert_and_extract(body)
  rows = aplyFilter(rows,filter,schema)
  
  return rows, nil
end



return _M
