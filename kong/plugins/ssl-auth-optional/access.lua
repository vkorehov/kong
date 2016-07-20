local _M = {}

function _M.execute(conf)
  if ngx.var.ssl_client_verify == "SUCCESS" then
    local user = string.match(ngx.var.ssl_client_s_dn, '/CN=([^/]+)/')
    ngx.ctx.ssl_authenticated = true
    ngx.ctx.ssl_authenticated_credential = {username=user}
  else
    ngx.ctx.ssl_authenticated = false
  end
end

return _M
