local BasePlugin = require "kong.plugins.base_plugin"
local access = require "kong.plugins.ssl-auth-optional.access"

local SSLAuthHandler = BasePlugin:extend()

function SSLAuthHandler:new()
  SSLAuthHandler.super.new(self, "ssl-auth-optional")
end

function SSLAuthHandler:access(conf)
  SSLAuthHandler.super.access(self)
  access.execute(conf)
end
SSLAuthHandler.PRIORITY = 1000
return SSLAuthHandler
