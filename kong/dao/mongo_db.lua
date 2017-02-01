local BaseDB = require "kong.dao.base_db"
local Errors = require "kong.dao.errors"
local utils = require "kong.tools.utils"
local timestamp = require "kong.tools.timestamp"
local log = require "kong.cmd.utils.nlog"
local uuid = utils.uuid

-- enable or disable logging
local debug = false

local TTL_CLEANUP_INTERVAL = 60 -- 1 seconds

local ngx_stub = _G.ngx
_G.ngx = nil
local mongo = require 'mongo'
_G.ngx = ngx_stub

local MongoDB = BaseDB:extend()

MongoDB.dao_insert_values = {
  id = function()
    return uuid()
  end,
  _id = function()
    return id
  end
}
local client = nil
local conn_opts = nil
local mongo_con_string = nil

function MongoDB:new(kong_config)
  conn_opts = {
    host = kong_config.mongo_host,
    port = kong_config.mongo_port,
    user = kong_config.mongo_user,
    password = kong_config.mongo_password,
    database = kong_config.mongo_database,
  }
  MongoDB.super.new(self, "mongo", conn_opts)
  conn_opts = self:_get_conn_options()
  mongo_con_string = 'mongodb://'..conn_opts.host..':'..conn_opts.port..'/'..conn_opts.database
  local client, err = mongo.Client(mongo_con_string)
  
  if err~=nil or client==nil then
    error(tostring(err))
  end
  
  local dbStatus,err = client:command(conn_opts.database,' { "serverStatus": 1 } ')
  
  if err then error(tostring(err)) end
  self.client = client
end

function MongoDB:infos()
  return {
    desc = "database",
    name = self:_get_conn_options().database
  }
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

function MongoDB:start_ttl_timer()
  
  if ngx and self.timer_started==nil then
    log.printc("start_ttl_timer[TTL_CLEANUP_INTERVAL] --->",TTL_CLEANUP_INTERVAL)
    local ok, err = ngx.timer.at(TTL_CLEANUP_INTERVAL, do_clean_ttl, self)
     if not ok then
         ngx.log(ngx.ERR, "failed to create the timer: ", err)
         return
     end
    self.timer_started = true
    log.printc("start_ttl_timer[timer_started] --->",self.timer_started)
  end
end

--function MongoDB:init()
  --log.printc("MongoDB:init()??????????--->","ok")
   
--end

-- Delete old expired TTL entities
function MongoDB:clear_expired_ttl()
  local expire_threshold = timestamp.get_utc()
  local ttl_query = mongo.BSON('{"expire_at":{"$lt":'..expire_threshold..'}}')
  if debug then  
    log.printc("clear_expired_ttl[expire_threshold]--->",expire_threshold) 
  end
  local res,err = self:query_mongo('ttls',ttl_query,nil,nil,true)
  if debug then  
    log.printc("clear_expired_ttl[res]--->",res)
  end
  if err then
    return false, err
  end
  
  for _, v in ipairs(res) do
    local collection = self.client:getCollection(conn_opts.database, v.collection_name)
    local remove_query,remove_ttl_query = {}
    remove_query[v.primary_key_name] = v.primary_key_value
    remove_ttl_query._id=mongo.ObjectID(tostring(v._id))
    if debug then 
      log.printc("clear_expired_ttl[remove_query]--->",remove_query)
      log.printc("clear_expired_ttl[remove_ttl_query]--->",remove_ttl_query)
    end
    local res,err = collection:remove(remove_query)
    if err then
      ngx.log(ngx.ERR, "failed to clean up entity ttl: ", err)
      return false, err
    end
    collection = self.client:getCollection(conn_opts.database, 'ttls')
    res,err = collection:remove(remove_ttl_query)
    if err then
      ngx.log(ngx.ERR, "failed to clean up ttl: ", err)
      return false, err
    end
  end
  --[[
  if res~=nil and #res>0 then
    log.printc("clear_expired_ttl --DELETE--->",ttl_query)
    
    local res_rem,err = collection:remove(ttl_query)
    if err then
      return false, err
    end
  end
  --]]

  return true
end

-- pass commmands from dao/migrations/mongo.lua to create indexes
function MongoDB:execute_command(command)
  if debug then log.printc("execute_command[command]--->",command) end
  
  local status,err = self.client:command(conn_opts.database,command)
  if err then error(tostring(err)) end
  
end

-- adds record in schema_migrations collection
function MongoDB:record_migration(id, name)
  -- not used
  --[[
  log.printc("record_migration[id]--->",id)
  log.printc("record_migration[name]--->",name)
  local migrations = {}
  migrations.id=id
  migrations.migrations=name
  local res,err = self:insert('schema_migrations', nil ,migrations, nil, nil)
  
  if err then
    return nil, err
  end
  --]]
end

-- No mmigrations are run
function MongoDB:current_migrations()
  -- Check if schema_migrations table exists
  --[[
  local rows, err = self:query("schema_migrations,{}")
  log.printc("current_migrations--->",rows)
  if err then
    return nil, err
  end
  return rows
  --]]
  return {}
end



function MongoDB:ttl(model, collection_name, schema, ttl)
    if debug then
      log.printc("ttl[collection_name]--->",collection_name)
      log.printc("ttl[schema]--->",schema)
      log.printc("ttl[model]--->",model)
      log.printc("ttl[ttl]--->",ttl)
    end
    
    -- init timer
    self:start_ttl_timer()
    
    if not schema.primary_key or #schema.primary_key ~= 1 then
      return false, "Cannot set a TTL if the entity has no primary key, or has more than one primary key"
    end
    local ttl_document={}
    local ttl_query={}
    local primary_key_table = schema.primary_key
    local primary_key = primary_key_table[1]
    local primary_key_value = model[primary_key]
    local primary_uui_value = model['id']
    local expire_at = timestamp.get_utc()+(ttl * 1000)
    
    ttl_query['primary_key_name'] = primary_key
    ttl_document['primary_key_name'] = primary_key
    ttl_query['primary_key_value'] = primary_key_value
    ttl_document['primary_key_value'] = primary_key_value
    ttl_document['primary_uui_value'] = primary_uui_value
    ttl_document['collection_name'] = collection_name
    ttl_document['expire_at'] = expire_at
    
    if debug then
      log.printc("ttl[ttl_query] --->",ttl_query)
      log.printc("ttl[ttl_document] --->",ttl_document)
    end
    
    local res,err = self:find('ttls', schema, ttl_query,true)
    
    if debug then
      log.printc("ttl res ->",res)
    end
    
    if res==nil then
      local collection = self.client:getCollection(conn_opts.database, 'ttls')  
      local ttl_res,err = collection:save(ttl_document)
    else
      --log.printc("ttl res._id ->",tostring(res._id))
      --ttl_document._id=mongo.ObjectID(tostring(res._id))
      --log.printc("ttl ttl_document_id ->",ttl_document)
      local collection = self.client:getCollection(conn_opts.database, 'ttls')  
      local ttl_res_u,err = collection:update(ttl_query,ttl_document, { upsert = true })
      if err then
        return false, err
      end
    end    
  return true
end


function MongoDB:insert(collection_name, schema, model, constraints, options)
 if debug==true then
   log.printc("insert[collection_name] --->",collection_name)
   log.printc("insert[schema]--->",schema)
   log.printc("insert[model]--->",model)
   log.printc("insert[constraints]--->",constraints)
   log.printc("insert[options]--->",options)
 end
 local collection = self.client:getCollection(conn_opts.database, collection_name)
 model.created_at=timestamp.get_utc();
 local res,err = collection:save(model)
 if err then
    return nil, err
 end
 
 if res==true then 
   -- Handle options
  if options and options.ttl then
    local _, err = self:ttl(model, collection_name, schema, options.ttl)
    if err then
      return nil, err
    end
  end
  
  return model
 else
  error('Failed to save document in \''..collection_name..'\' collection')
 end
end



function MongoDB:find(collection_name, schema, filter,preserve_mongo_id)
  if debug then
    log.printc("find[collection_name]--->",collection_name)
    log.printc("find[schema]--->",schema)
    log.printc("find[filter]--->",filter)
  end
  local row ,err = self:query_mongo(collection_name,filter,schema,nil,preserve_mongo_id)
  if err~=nil then
    return nil,err
  end
  
  if row==nil or #row==0 then return row,nil end
  
  return row[1];
  
end

function MongoDB:find_all(collection_name, filter, schema)
  if debug then
    log.printc("finda_all[collection_name]--->",collection_name)
    log.printc("finda_all[filter]--->",filter)
    log.printc("finda_all[schema]--->",schema)
  end
  -- query for all documents
  if filter==nil then
    filter="{}"
  end
  if debug then log.printc("finda_all[filter]--->",filter) end
  return self:query_mongo(collection_name,filter,schema,nil)
end

function MongoDB:count(collection_name, filter, schema)
   if debug then 
    log.printc("count[collection_name]-->",collection_name)
    log.printc("count[filter]--->",filter)
    log.printc("count[schema]--->",schema)
   end
   if filter==nil then
    filter="{}"
   end
   
   local collection = self.client:getCollection(conn_opts.database, collection_name)
   local count = collection:count(filter)
   if count == nil then return 0 end
   if debug then log.printc("count[val]--->",count) end
   return count
end

function MongoDB:update(collection_name, schema, constraints, filter_keys, values, nils, full, model, options)
   if debug then
     log.printc("update [collection_name]--->",collection_name)
     log.printc("update [schema]--->",schema)
     log.printc("update [constraints]--->",constraints)
     log.printc("update [filter_keys]--->",filter_keys)
     log.printc("update [values]--->",values)
     log.printc("update [nils]--->",nils)
     log.printc("update [full]--->",full)
     log.printc("update [model]--->",model)
     log.printc("update [options]--->",options)
   end 
   
   local collection = self.client:getCollection(conn_opts.database, collection_name)
   local res, err = collection:update(filter_keys, model)
   if err ~= nil then 
    return nil, err
   end
   return self:find(collection_name, schema, filter_keys)
end

function MongoDB:delete(collection_name, schema, filter, constraints)
  if debug then
    log.printc("delete[collection_name]--->",collection_name)
    log.printc("delete[schema]--->",schema)
    log.printc("delete[filter]--->",filter)
    log.printc("delete[constraints]--->",constraints)
  end
  local row, err = self:find(collection_name, schema, filter)
  if err~=nil or row ==nil then
    error('Failed to find document for deletion')
  end
  
  --also delete configured plugins for apis
  if collection_name=='apis' then
    local cascade_delete_query = '{\"api_id\":\"'..row.id..'\"}'
    if debug then log.printc("delete -cascade_delete_query>",cascade_delete_query) end
    self:delete('plugins',nil,cascade_delete_query,cascade_delete_query,nil)
  end
  
  local collection = self.client:getCollection(conn_opts.database, collection_name)
  local res,err = collection:remove(filter)
  if err then
    return nil, err
  end
  
  
  
  if res and res==true then
    return row
  end  

end

function MongoDB:query(query, schema)
  if debug then
    log.printc("query[query]--->",query)
    log.printc("query[schema]--->",schema)
  end
  MongoDB.super.query(self, query)
  local querytokens,err = self:parseQuery(query)
  if #querytokens<2 then
    error("Failed to tokenize query "..query)
  end
  
  local collection_name = querytokens[1]
  local mongo_query = querytokens[2]
  return self:query_mongo(collection_name,mongo_query,schema,nil,false);
end


function MongoDB:query_mongo(collection_name,mongo_query,schema,options,preserve_mongo_id)
  if preserve_mongo_id==nil then preserve_mongo_id=false end
  if debug then
    log.printc("query_mongo[collection_name]--->",collection_name)
    log.printc("query_mongo[mongo_query]--->",mongo_query)
    log.printc("query_mongo[schema]--->",schema)
    log.printc("query_mongo[options]--->",options)
    log.printc("query_mongo[preserve_mongo_id]--->",preserve_mongo_id)
  end
  
  -- done to simulate SQL LIKE query in case of roles
  if mongo_query ~= nil then
    if mongo_query.roles ~= nil then
       mongo_query.roles=mongo.Regex(mongo_query.roles)
    end
  end
  
  local collection = self.client:getCollection(conn_opts.database, collection_name)
  local query = mongo.BSON(mongo_query)
  
  if debug then log.printc("query_mongo[query]--->",query)end
  local res, err = collection:find(query,options);
  
  if res == nil or res:isAlive()==false then 
    return {} 
  end
  
  local results={}
  for document in res:iterator() do
      --remove mongo internal id
      if preserve_mongo_id~=true then document._id=nil end
      table.insert(results,document)
  end
  
  return results,err
end



function MongoDB:parseQuery(str)
  local split={}
  for word in string.gmatch(str, '[^,%s]+') do
    table.insert(split,word)
  end
  return split;
end


function MongoDB:queries(queries)
  if utils.strip(queries) ~= "" then
    local err = select(2, self:query(queries))
    if err then
      return err
    end
  end
end

function MongoDB:find_page(collection_name, filter, page, page_size, schema)
  if debug then
    log.printc("find_page[collection_name]--->",collection_name)
    log.printc("find_page[filter]--->",filter)
    log.printc("find_page[page]--->",page)
    log.printc("find_page[page_size]--->",page_size)
    log.printc("find_page[schema]--->",schema)
  end
  
  if page == nil then
    page = 1
  end
  if filter==nil then
    filter="{}"
  end
  
  local total_count, err = self:count(collection_name, tbl, schema)
  if err then
    return nil, err
  end
  
  local total_pages = math.ceil(total_count/page_size)
  local offset = page_size * (page - 1)
  
  
  local options = mongo.BSON('{ "skip" : '..offset..', "limit" : '..page_size..' }')
  
  local rows = self:query_mongo(collection_name,filter,schema,options)
  if debug then 
    log.printc("find_page[#rows]--->",#rows)
  end
  
  local next_page = page + 1
  return rows, nil, (next_page <= total_pages and next_page or nil)
  
end




return MongoDB
