local BasePlugin = require "kong.plugins.base_plugin"
local access = require "kong.plugins.oauth2.access"

local OAuthHandler = BasePlugin:extend()

function OAuthHandler:new()
  OAuthHandler.super.new(self, "oauth2")
end

function OAuthHandler:access(conf)
  OAuthHandler.super.access(self)
  if ngx.req.get_method() == "GET" and conf.ignore_patern ~= nil and conf.ignore_patern ~= "" and ngx.re.match(ngx.var.request_uri, conf.ignore_patern) then
    --ngx.log(ngx.ERR, "IJNIINIININNNNIN: "..ngx.var.request_uri, "")   
  else
    access.execute(conf)
end
end

OAuthHandler.PRIORITY = 1000

return OAuthHandler
