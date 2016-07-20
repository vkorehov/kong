local singletons = require "kong.singletons"
local responses = require "kong.tools.responses"
local cache = require "kong.tools.database_cache"
local _M = {}

function _M.execute(conf)
  if ngx.ctx.ssl_authenticated then
    local username = ngx.ctx.ssl_authenticated_credential.username
    ngx.log(ngx.ERR, "SSL Authenticated: "..username)

    local consumer = cache.get_or_set(cache.consumer_key(username), function()
      local result, err = singletons.dao.consumers:find_all {username = username}
      if err then
        return responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
      end
      if table.getn(result) > 0 then
        return result[1]
      end
      return nil
    end)

    if consumer == nil then
      return responses.send_HTTP_FORBIDDEN("Invalid authentication credentials")
    end
    ngx.req.set_header('X-Username', consumer.username)
    ngx.req.set_header('X-User-ID', consumer.custom_id)
    ngx.req.set_header('X-Authenticated-By', 'SSL')
  else
    ngx.log(ngx.ERR, "SSL Unauthenticated")
  end
  if ngx.ctx.ldap_authenticated then
    local username = ngx.ctx.ldap_authenticated_credential.username
    ngx.log(ngx.ERR, "LDAP Authenticated:"..username)

    local consumer = cache.get_or_set(cache.consumer_key(username), function()
      local result, err = singletons.dao.consumers:find_all {username = username}
      if err then
        return responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
      end
      if table.getn(result) > 0 then
        return result[1]
      end
      return nil
    end)

    if consumer == nil then
      return responses.send_HTTP_FORBIDDEN("Invalid authentication credentials")
    end
    ngx.req.set_header('X-Username', consumer.username)
    ngx.req.set_header('X-User-ID', consumer.custom_id)
    ngx.req.set_header('X-Authenticated-By', 'LDAP')
  else
    ngx.log(ngx.ERR, "LDAP Unauthenticated")
  end
  if conf.mandatory and not ngx.ctx.ldap_authenticated and not ngx.ctx.ssl_authenticated then
    return responses.send_HTTP_FORBIDDEN("Authentication required")
  end
end

return _M
