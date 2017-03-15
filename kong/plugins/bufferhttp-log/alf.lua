-- ==================================================
-- * The following fields cannot be retrieved as of ngx_lua 0.10.2:
--     * response.statusText
--     * response.headersSize
--
-- * Kong can modify the request/response due to its nature, hence,
--   we distinguish the original req/res from the current req/res
--     * request.headersSize will be the size of the _original_ headers
--       received by Kong
--     * request.headers will contain the _current_ headers
--     * response.headers will contain the _current_ headers
--
-- * bodyCaptured properties are determined using HTTP headers
-- * timings.blocked is ignored
-- * timings.connect is ignored

local cjson = require "cjson.safe"
local uuid = require("kong.tools.utils").uuid
local timestamp = require "kong.tools.timestamp"
local singletons = require "kong.singletons"
local resp_get_headers = ngx.resp.get_headers
local req_start_time = ngx.req.start_time
local req_get_method = ngx.req.get_method
local req_get_headers = ngx.req.get_headers
local req_get_uri_args = ngx.req.get_uri_args
local req_raw_header = ngx.req.raw_header
local setmetatable = setmetatable
local tonumber = tonumber

local pairs = pairs
local type = type
local gsub = string.gsub

local _M = {
  _VERSION = "2.0.0",
  _ALF_VERSION = "1.1.0",
  _ALF_CREATOR = "bufferhttml-agent-kong"
}

local _mt = {
  __index = _M
}

function _M.new(log_request,log_response,log_oauth2_response,max_msg_size,secure_message,secure_patterns,default_auth_key,default_app)
  local alf = {
    log_request = log_request,
    log_response = log_response,
    log_oauth2_response = log_oauth2_response,
    max_msg_size = max_msg_size,
    secure_message = secure_message,
    secure_patterns = secure_patterns,
    default_auth_key = default_auth_key,
    default_app = default_app,
    entries = {}
  }

  return setmetatable(alf, _mt)
end

local function get_header(t, name, default)
  local v = t[name]
  if not v then
    return default
  elseif type(v) == "table" then
    return v[#v]
  end
  return v
end

--- Add an entry to the ALF's `entries`
-- @param[type=table] _ngx The ngx table, containing .var and .ctx
-- @param[type=string] req_body_str The request body
-- @param[type=string] res_body_str The response body
-- @treturn table The entry created
-- @treturn number The new size of the `entries` array
function _M:add_entry(_ngx, req_body_str, resp_body_str,conf)
  if not self.entries then
    return nil, "no entries table"
  elseif not _ngx then
    return nil, "arg #1 (_ngx) must be given"
  elseif req_body_str ~= nil and type(req_body_str) ~= "string" then
    return nil, "arg #2 (req_body_str) must be a string"
  elseif resp_body_str ~= nil and type(resp_body_str) ~= "string" then
    return nil, "arg #3 (resp_body_str) must be a string"
  elseif type(conf) ~= "table" then
    return nil, "arg #4 (conf) must be a table"
  end

  self.log_request = conf.log_request
  self.log_response = conf.log_response
  self.log_oauth2_response = conf.log_oauth2_response
  self.max_msg_size = conf.max_msg_size_mb
  self.secure_message = conf.secure_message
  self.secure_patterns = conf.secure_patterns
  self.default_auth_key = conf.default_auth_key	
  self.default_app = conf.default_app
	
  -- retrieval
  local var = _ngx.var
  local ctx = _ngx.ctx
  local request_headers = req_get_headers()
  local request_content_len = get_header(request_headers, "content-length", 0)
  local request_transfer_encoding = get_header(request_headers, "transfer-encoding")
  local request_content_type = get_header(request_headers, "content-type",
                                          "application/octet-stream")

  local resp_headers = resp_get_headers()
  local resp_content_len = get_header(resp_headers, "content-length", 0)
  local resp_transfer_encoding = get_header(resp_headers, "transfer-encoding")
  local resp_content_type = get_header(resp_headers, "content-type",
                            "application/octet-stream")

  local request_auth2_credetionals = get_header(request_headers, "authorization") 
	
  -- request.postData. we don't check has_body here, but rather
  -- stick to what the request really contains, since it was
  -- already read anyways.
  local post_data, response_content, response_token
  local isOauth2 = "false"
  local req_body_size = tonumber(request_content_len)
  local resp_body_size = tonumber(resp_content_len)

  if ngx.re.match(ngx.var.request_uri, "/oauth2/token") then
    isOauth2 = "true"		
  end
	
  if req_body_str then
    req_body_size = #req_body_str
		
    if self.log_request then
      post_data = req_body_str		
    end
  end

  if resp_body_str then
    resp_body_size = #resp_body_str
		
    if self.log_response then
      response_content = resp_body_str
    end
		
    if self.log_oauth2_response and isOauth2 == "true" then
      response_content = resp_body_str
			
      if request_auth2_credetionals then
	request_auth2_credetionals = string.gsub(request_auth2_credetionals, "Basic", "")
	request_auth2_credetionals = request_auth2_credetionals:gsub("%s+", "")
	
	if request_auth2_credetionals then
	  request_auth2_credetionals = string.match(ngx.decode_base64(request_auth2_credetionals), "(.*)%:")
	  request_headers["dm_identity"]= request_auth2_credetionals
        end
				
      end
      
      response_token = string.match(response_content, "access_token\":(.*)%\",")
	
      if response_token then
	response_token = response_token:gsub("%s+", "")
	response_token = response_token:gsub("%\"+", "")
	request_headers["dm_oauth2_token"]= response_token
      end
    end		
  end

  -- timings
  local send_t = ctx.KONG_PROXY_LATENCY or 0
  local wait_t = ctx.KONG_WAITING_TIME or 0
  local receive_t = ctx.KONG_RECEIVE_TIME or 0
  local api_id = ctx.api.id
  local request_path = ctx.api.request_path
  
  local idx = #self.entries + 1
  local isError = "false"
  --local result = "success"
  local isTimeOut = "false"
  local now = timestamp.get_utc()
	
  if ngx.status >= 400 then
    isError = 'true'
    --result = "error"
  end

  if ngx.status == 504 then
    isTimeOut = 'true'
    --result = "error"
  end

  if not request_headers["dm_auth_key"] then
    request_headers["dm_auth_key"]= self.default_auth_key
  end	

  if not request_headers["dm_app"] then
    request_headers["dm_app"]= self.default_app
  end

	
  --request_headers["dm_http_method"]= req_get_method()
  request_headers["dm_http_method"]= req_get_method()
  request_headers["dm_http_path"]= request_path
  request_headers["dm_http_remote_addr"]= ngx.var.remote_addr
  request_headers["dm_http_content_type"]= request_content_type
  request_headers["dm_http_status_code"]= ""..ngx.status
  request_headers["dm_http_content_type"]= resp_content_type
  request_headers["dm_http_character_enc"]= resp_transfer_encoding
  request_headers["dm_source"]= "KONG_API"
  --request_headers["dm_name"]= "http"
  request_headers["dm_is_error"]= isError
  --request_headers["dm_result"]= result
  request_headers["dm_is_timeout"]= isTimeOut
  request_headers["dm_oauth2_message"]= isOauth2 
  request_headers["dm_upstream_url"]= ngx.ctx.api.upstream_url	
  request_headers["dm_request_uri"]= ngx.var.request_uri
  request_headers["dm_service"]= ngx.var.upstream_addr
  request_headers["dm_api_name"]=ngx.ctx.api.name
  request_headers["dm_server"]=singletons.configuration.ip
	
  self.entries[idx] = {
    source = "KONG_API",
    timestamp = now,
    id = uuid(),
    name = "http",
    headers = request_headers,
    payload = {
      request = {
        body = post_data,
        headers = req_get_headers()
      },
      response = {
        body = response_content,
        headers = resp_headers
      }},
      metrics = {
        request_size = req_body_size,
        response_size = resp_body_size,
        execution_time = wait_t,
        client_response_time = receive_t,
        self_execution_time = send_t
      }
}

local max_size_mb = self.max_msg_size * 2^20

if #cjson.encode(self.entries[idx]) > max_size_mb then
  self.entries[idx].payload.request.body = ""
  self.entries[idx].payload.response.body = ""
end

  return self.entries[idx], idx
end

--local _alf_max_size = 20 * 2^20

--- Encode the current ALF to JSON
-- @param[type=string] service_token The ALF `serviceToken`
-- @param[type=string] environment (optional) The ALF `environment`
-- @treturn string The ALF, JSON encoded
function _M:serialize()
  if not self.entries then
    return nil, "no entries table"
  end

  local entries_json = {}
  local size = 0
	
  for i,v in ipairs(self.entries) do
      local authkey = v.headers["dm_auth_key"]
      local app = v.headers["dm_app"]
      local json = cjson.encode(v)
--    if #json > _alf_max_size then
--      return nil, "ALF too large (> 20MB)"
--    end
      if self.secure_message then
       --for headers
         local patterns = {}
 
         if self.secure_patterns == nil then
	    patterns = {"(assword\":)\"(.-)\"","(token\":)\"(.-)\""}
         else
	    patterns = self.secure_patterns		
         end
		
         for i,v in ipairs(patterns) do
            json = gsub(json, v, "%1\"*******\"")
            json = gsub(json, gsub(v, "\"", "\\\""), "%1\\\"*******\\\"")
         end
      end
		
      entries_json[i] = {
	body = gsub(json, "\\/", "/"),
	dm_auth_key = authkey,
        dm_app = app
      }
      size = size+ #entries_json[i].body
  end		
	
  return entries_json, size, #self.entries
end

--- Empty the ALF
function _M:reset()
  self.entries = {}
end

return _M
