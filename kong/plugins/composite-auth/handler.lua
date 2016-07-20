local BasePlugin = require "kong.plugins.base_plugin"
local access = require "kong.plugins.composite-auth.access"

local CompositeAuthHandler = BasePlugin:extend()

function CompositeAuthHandler:new()
  CompositeAuthHandler.super.new(self, "composite-auth")
end

function CompositeAuthHandler:access(conf)
  CompositeAuthHandler.super.access(self)
  access.execute(conf)
end
CompositeAuthHandler.PRIORITY = 999
return CompositeAuthHandler
