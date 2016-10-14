local BasePlugin = require "kong.plugins.base_plugin"
local responses = require "kong.tools.responses"

local cjson = require "cjson"
local meta = require "kong.meta"
local req_get_uri_args = ngx.req.get_uri_args
local ngx_log = ngx.log

--local server_header = _KONG._NAME.."/".._KONG._VERSION
local server_header = meta._NAME.."/"..meta._VERSION

--Extend Base Plugin
local Mocker = BasePlugin:extend()

--Set Priority
Mocker.PRIORITY = 1
--split function for dev environment
function string:split( inSplitPattern, outResults )
  if not outResults then
    outResults = { }
  end
  local theStart = 1
  local theSplitStart, theSplitEnd = string.find( self, inSplitPattern, theStart )
  while theSplitStart do
    table.insert( outResults, string.sub( self, theStart, theSplitStart-1 ) )
    theStart = theSplitEnd + 1
    theSplitStart, theSplitEnd = string.find( self, inSplitPattern, theStart )
  end
  table.insert( outResults, string.sub( self, theStart ) )
  return outResults
end
-- send response function
local function send_response(status_code,content, contentTypeJson,transformMessage)
    ngx.status = status_code
    if contentTypeJson == "application/json; charset=utf-8" then
     ngx.header["Content-Type"] = "application/json; charset=utf-8"
    else
    ngx.header["Content-Type"] = "text/html; charset=UTF-8"    
    end
    
    ngx.header["Server"] = server_header
  
    if contentTypeJson == "application/json; charset=utf-8" and transformMessage then
        if type(content) == "table" then
          ngx.say(cjson.encode(content))
        elseif content then
          ngx.say(cjson.encode {message = content})
        end
    else
        ngx.say(content)
    end

    ngx.exit(status_code)
end

function Mocker:new()
  Mocker.super.new(self, "mocker")
end

function Mocker:access(conf)
  Mocker.super.access(self)
  
  local errorCode = 403
  local errorMessage = "Default Mock JSON Message"
  local contentType = "application/json; charset=utf-8"
  local transformMessage = true
    
  if conf.use_url_params and type(conf.use_url_params) == "boolean" then
    local queryParams = req_get_uri_args()
    local url = ngx.ctx.upstream_url
    local pathIndex = url:find('[^/]/[^/]')
    local path = url:sub(pathIndex + 1)    
		
    local mockValue = {}
    local queryNameMAP = {} 
    local queryValueMAP = {}
    local queryValue = ""
    local queryString = ""
    local mockName = ""
    local parsedQueryValue = {}	
		
    local loopHelper = true
    local isMatched = false
    local queryParamsCount = 0
    local mapParamsCount = 0

    -- populate main fields		
    if conf.mock_name_mapping == nil then
        queryNameMAP = {['?mock1=mock1&mock2=mock2']='mock1',['/product']='mock2'}
    else
        queryNameMAP = loadstring("return "..conf.mock_name_mapping)()
    end
    if conf.mock_value_mapping == nil then
        queryValueMAP = {['mock1']={['code']=404,['contentType']='application/json; charset=utf-8',['message']='{\"message\":\"Default Mock JSON Message\"}'}}
    else
        queryValueMAP = loadstring("return "..conf.mock_value_mapping)()
    end
		
    --find needed mock response 
    if queryParams ~= nil or path then
         for keyMAP, valMAP in pairs(queryNameMAP) do
		if type(keyMAP) == "string" then
			-- if query param
			if string.sub(keyMAP, 0, 1) == "?" and queryParams ~= nil then
				loopHelper = true
				queryString = string.sub(keyMAP, 2)
				parsedQueryValue = queryString:split("&")
				if parsedQueryValue ~= nil and type(parsedQueryValue) == "table" then
					queryParamsCount = 0
					for key, val in pairs(queryParams) do
						queryParamsCount = queryParamsCount+1
						if type(val) ~= "table"	and loopHelper == true then
						  loopHelper = false
						  queryValue = key.."="..val
						  for i = 1, #parsedQueryValue do
						     mapParamsCount = #parsedQueryValue			
						     if parsedQueryValue[i] and parsedQueryValue[i] == queryValue then
							loopHelper = true
							break
						     end
						  end
						else
						  break
						end
					end
					if loopHelper and queryParamsCount == mapParamsCount then
					  mockName = valMAP
					  break
				 	end
				end
			-- if path
			elseif string.sub(keyMAP, 0, 1) == "/" then
				if path and keyMAP == path then
				  mockName = valMAP
				  break
				end
			end
		end
         end
	
    end
		
    if mockName then
      mockValue = queryValueMAP[mockName]
    end
	
     if mockValue then
	      if mockValue["code"] then
		errorCode = mockValue["code"]
	      end
	      if mockValue["message"] then
		transformMessage = false
		errorMessage = mockValue["message"]
	      end
	       if mockValue["contentType"] then
		contentType = mockValue["contentType"]
	      end
    end       
  else
      if conf.error_code and type(conf.error_code) == "number" then
          errorCode = conf.error_code
      end

      if type(conf.content_type_json) == "boolean" and conf.content_type_json == false then
          contentType = "text/html; charset=UTF-8"
      end

      if conf.error_message and type(conf.error_message) == "string" then
          errorMessage = conf.error_message
      end
  end
    
  send_response(errorCode, errorMessage,contentType,transformMessage)

end

function Mocker:body_filter(conf)
  Mocker.super.body_filter(self)

end

function Mocker:log(conf)
  Mocker.super.log(self)

end

return Mocker
