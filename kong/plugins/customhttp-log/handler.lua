local basic_serializer = require "kong.plugins.log-serializers.basic"
local BasePlugin = require "kong.plugins.base_plugin"
local cjson = require "cjson.safe"
local url = require "socket.url"

--Extend Base Plugin
local CustomHttpLogHandler = BasePlugin:extend()

--Set Priority
CustomHttpLogHandler.PRIORITY = 1

--set global variables
local HTTPS = "https"
local resp_get_headers = ngx.resp.get_headers
local req_start_time = ngx.req.start_time
local req_get_method = ngx.now
local req_get_headers = ngx.req.get_headers
local WARN = ngx.WARN

local read_body = ngx.req.read_body
local get_body_data = ngx.req.get_body_data
local gsub = string.gsub

--request structure
entries = {}

-- Generates http payload .
-- @param `method` http method to be used to send data
-- @param `parsed_url` contains the host details
-- @param `message`  Message to be logged
-- @return `body` http payload
local function generate_post_payload(method, parsed_url, body)
  ngx.log(ngx.ERR, "Error "..tostring(body)..": ", "")
  return string.format(
    "%s %s HTTP/1.1\r\nHost: %s\r\nConnection: Keep-Alive\r\nContent-Type: application/json\r\nContent-Length: %s\r\n\r\n%s",
    method:upper(), parsed_url.path, parsed_url.host, string.len(body), body)
end

-- Parse host url
-- @param `url`  host url
-- @return `parsed_url`  a table with host details like domain name, port, path etc
local function parse_url(host_url)
  local parsed_url = url.parse(host_url)
  if not parsed_url.port then
    if parsed_url.scheme == "http" then
      parsed_url.port = 80
     elseif parsed_url.scheme == HTTPS then
      parsed_url.port = 443
     end
  end
  if not parsed_url.path then
    parsed_url.path = "/"
  end
  return parsed_url
end

--Get Header fields
local function get_header(t, name, default)
  local v = t[name]
  if not v then
    return default
  elseif type(v) == "table" then
    return v[#v]
  end
  return v
end

--Create request method
local function create_req(max_size_mb,log_bodies,req_body_str,resp_body_str)

  local msg_max_size = max_size_mb * 2^20
  local post_data, response_content
  local req_body_size, resp_body_size = 0, 0
  
  --Get Request header info
  local request_headers = req_get_headers()
  local request_content_len = get_header(request_headers, "content-length", 0)
  local request_transfer_encoding = get_header(request_headers, "transfer-encoding")
  local request_content_type = get_header(request_headers, "content-type",
                                          "application/octet-stream")

  local req_has_body = tonumber(request_content_len) > 0
                       or request_transfer_encoding ~= nil
                       or request_content_type == "multipart/byteranges"
  
  --Get Response header info
  local resp_headers = resp_get_headers()
  local resp_content_len = get_header(resp_headers, "content-length", 0)
  local resp_transfer_encoding = get_header(resp_headers, "transfer-encoding")
  local resp_content_type = get_header(resp_headers, "content-type",
                            "application/octet-stream")

  local resp_has_body = tonumber(resp_content_len) > 0
                        or resp_transfer_encoding ~= nil
                        or resp_content_type == "multipart/byteranges"     

--Decide to log body or not
 if log_bodies then
    if req_body_str then
      req_body_size = #req_body_str
      post_data = req_body_str

   end
    if resp_body_str then
      resp_body_size = #resp_body_str
      response_content = resp_body_str
    end
end                  
                       
  -- timings
  local send_t = ngx.ctx.KONG_PROXY_LATENCY or 0
  local wait_t = ngx.ctx.KONG_WAITING_TIME or 0
  local receive_t = ngx.ctx.KONG_RECEIVE_TIME or 0
  local api_id = ngx.ctx.api.id
  local request_path = ngx.ctx.api.request_path
  local idx = 1                   

  -- main request
  entries[idx] = {
    source = "debessmana",
    timestamp = req_start_time()*1000,
    id = api_id,
    name = "KONG_API",
    headers = request_headers,
    payload = {
    request = {
	  metadata = {
      http_method = req_get_method(),
      http_path = request_path,
      http_remote_add = ngx.var.remote_addr,
	  http_content_type = request_content_type,
	  },
    body = post_data,
    headers = request_headers
    },
    response = {
	  metadata = {
      http_statuc_code = ""..ngx.status,
      http_content_type = resp_content_type,
      http_character_enc = resp_transfer_encoding
	  },
    body = response_content,
    headers = resp_headers
    }},
    metrics = {
      request_size = req_body_size,
      response_size = resp_body_size,
      execution_time = send_t + wait_t + receive_t
    }
}

if #cjson.encode(entries[idx]) > msg_max_size then
ngx.log(WARN, "Message size is greater then max_size param: "..#cjson.encode(entries[idx])..">msx_max_size:"..msg_max_size)
entries[idx].request.postData = ""
entries[idx].response.content = ""
end

  return entries[idx]
end

-- Log to a Http end point.
-- @param `premature`
-- @param `conf`     Configuration table, holds http endpoint details
-- @param `message`  Message to be logged
local function log(premature, conf, body, name)
  if premature then return end
  name = "["..name.."] "
  
  local ok, err
  local parsed_url = parse_url(conf.http_endpoint)
  local host = parsed_url.host
  local port = tonumber(parsed_url.port)

  local sock = ngx.socket.tcp()
  sock:settimeout(conf.timeout)

  ok, err = sock:connect(host, port)
  if not ok then
    ngx.log(ngx.ERR, name.."failed to connect to 111"..host..":"..tostring(port)..": ", err)
    return
  end

  if parsed_url.scheme == HTTPS then
    local _, err = sock:sslhandshake(true, host, false)
    if err then
      ngx.log(ngx.ERR, name.."failed to do SSL handshake with "..host..":"..tostring(port)..": ", err)
    end
  end

  ok, err = sock:send(generate_post_payload(conf.method, parsed_url, body))
  if not ok then
    ngx.log(ngx.ERR, name.."failed to send data to "..host..":"..tostring(port)..": ", err)
  end

  ok, err = sock:setkeepalive(conf.keepalive)
  if not ok then
    ngx.log(ngx.ERR, name.."failed to keepalive to "..host..":"..tostring(port)..": ", err)
    return
  end
end

-- Only provide `name` when deriving from this class. Not when initializing an instance.
function CustomHttpLogHandler:new(name)
  CustomHttpLogHandler.super.new(self, name or "http-log")
end

--Needed to get request body
function CustomHttpLogHandler:access(conf)
  CustomHttpLogHandler.super.access(self)

  if not _server_addr then
    _server_addr = ngx.var.server_addr
  end

  if conf.log_bodies then
    read_body()
    ngx.ctx.customhttp = {req_body = get_body_data()}
  end
end

--Needed to get response body
function CustomHttpLogHandler:body_filter(conf)
  CustomHttpLogHandler.super.body_filter(self)

  if conf.log_bodies then
    local chunk = ngx.arg[1]
    local ctx = ngx.ctx
    local res_body = ctx.customhttp and ctx.customhttp.res_body or ""
    res_body = res_body .. (chunk or "")
    ctx.customhttp.res_body = res_body
  end
end

--Convert request to json object
function serialize(request)
  local json = cjson.encode(request)
  return gsub(json, "\\/", "/")
end

--Executed when the last response byte has been sent to the client.
function CustomHttpLogHandler:log(conf)
  local ctx = ngx.ctx
  CustomHttpLogHandler.super.log(self)
  local req_body, res_body
  if ctx.customhttp then
    req_body = ctx.customhttp.req_body
    res_body = ctx.customhttp.res_body
  end
  local request = create_req(conf.max_size_mb,conf.log_bodies,req_body,res_body)
  local ok, err = ngx.timer.at(0, log, conf, serialize(request), self._name)
  if not ok then
    ngx.log(ngx.ERR, "["..self._name.."] failed to create timer: ", err)
  end
end

return CustomHttpLogHandler
