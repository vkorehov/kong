local _M = {}

--- Retrieves the hostname of the local machine
-- @return string  The hostname
function _M.printc(msg,logObject)
  local log_message=msg;
  if type(logObject)=='table' then
     log_message = log_message..'  '..table.tostring(logObject)
  elseif type(logObject)=='string' then
     log_message = log_message..'  '..tostring(logObject)
  else 
     log_message = log_message..'  '..tostring(logObject)
  end
  
  ngx.log(ngx.INFO, log_message);
  print(log_message)
  --ngx.say(log_message);
  return log_message
end

function _M.print(logObject)
  local log_message='';
  if type(logObject)=='table' then
     log_message = table.tostring(logObject)
  elseif type(logObject)=='string' then
     log_message = tostring(logObject)
  else 
     log_message = tostring(logObject)
  end
  
  ngx.log(ngx.INFO, log_message);
  print(log_message)
  return log_message
end

function _M.t(logObject)
  if 'table'==type(logObject) then
    for key,value in pairs(logObject) do 
      local r=key..'='..tostring(value)
      ngx.log(ngx.INFO, r);
      print(r)
      
    end
  end
end


function table.val_to_str ( v )
  if "string" == type( v ) then
    v = string.gsub( v, "\n", "\\n" )
    if string.match( string.gsub(v,"[^'\"]",""), '^"+$' ) then
      return "'" .. v .. "'"
    end
    return '"' .. string.gsub(v,'"', '\\"' ) .. '"'
  else
    return "table" == type( v ) and table.tostring( v ) or
      tostring( v )
  end
end

function table.key_to_str ( k )
  if "string" == type( k ) and string.match( k, "^[_%a][_%a%d]*$" ) then
    return k
  elseif "number" == type( k ) then
    return k
  else
    return "[" .. table.val_to_str( k ) .. "]"
  end
end

function table.tostring( tbl )
  local result, done = {}, {}
  for k, v in ipairs( tbl ) do
    table.insert( result, table.val_to_str( v ) )
    done[ k ] = true
  end
  for k, v in pairs( tbl ) do
    if not done[ k ] then
      table.insert( result,
        table.key_to_str( k ) .. "=" .. table.val_to_str( v ) )
    end
  end
  return "{" .. table.concat( result, "," ) .. "}"
end


return _M
