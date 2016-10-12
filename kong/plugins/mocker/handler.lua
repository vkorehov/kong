local BasePlugin = require "kong.plugins.base_plugin"
local responses = require "kong.tools.responses"

--Extend Base Plugin
local Mocker = BasePlugin:extend()

--Set Priority
Mocker.PRIORITY = 1

function Mocker:new()
  Mocker.super.new(self, "mocker")
end

function Mocker:access(conf)
  Mocker.super.access(self)
  
  local errorCode = 403
  local errorMessage = "This service is not available right now"
  local headers = {}
  
  if conf.error_code and type(conf.error_code) == "number" then
      errorCode = conf.error_code
  end

  if conf.error_message and type(conf.error_message) == "string" then
      errorMessage = conf.error_message
  end

  responses.send(errorCode, errorMessage)

end

function Mocker:body_filter(conf)
  Mocker.super.body_filter(self)

end

function Mocker:log(conf)
  Mocker.super.log(self)

end

return Mocker
