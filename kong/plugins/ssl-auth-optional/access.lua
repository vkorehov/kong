local _M = {}

function _M.execute(conf)
  if ngx.var.ssl_client_verify == "SUCCESS" then
    ngx.log(ngx.ERR, "SSL S-DN: "..ngx.var.ssl_client_s_dn)
    local user = string.match(ngx.var.ssl_client_s_dn, '/CN=([^/]+)/')
    ngx.log(ngx.ERR, "SSL USER: "..user)
    ngx.ctx.ssl_authenticated = true
    ngx.ctx.ssl_authenticated_credential = {username=user}
  else
    ngx.ctx.ssl_authenticated = false
  end
end

return _M
