-- Buffers request/response bodies if asked so in the plugin's config.
-- Caches the server's address to avoid further syscalls.
--
-- Maintains one ALF Buffer per bufferhttp plugin per worker.

local BasePlugin = require "kong.plugins.base_plugin"
local Buffer = require "kong.plugins.bufferhttp-log.buffer"

local read_body = ngx.req.read_body
local get_body_data = ngx.req.get_body_data
local req_set_header = ngx.req.set_header
local req_get_headers = ngx.req.get_headers
local uuid = require("kong.tools.utils").uuid

local _alf_buffers = {} -- buffers per-api

local BufferHTTPHandler = BasePlugin:extend()

function BufferHTTPHandler:new()
  BufferHTTPHandler.super.new(self, "bufferhttp-log")
end

function BufferHTTPHandler:access(conf)
  BufferHTTPHandler.super.access(self)

  if conf.add_request_id then
    if not req_get_headers()["request-id"] then
      req_set_header("request-id", uuid())    
    end
  end
    
  if conf.log_bodies then
    read_body()
    ngx.ctx.bufferhttp = {req_body = get_body_data()}
  end
end

function BufferHTTPHandler:body_filter(conf)
  BufferHTTPHandler.super.body_filter(self)

  if conf.log_bodies then
    local chunk = ngx.arg[1]
    local ctx = ngx.ctx
    local res_body = ctx.bufferhttp and ctx.bufferhttp.res_body or ""
    res_body = res_body .. (chunk or "")
    ctx.bufferhttp.res_body = res_body
  end
end

function BufferHTTPHandler:log(conf)
  BufferHTTPHandler.super.log(self)

  local ctx = ngx.ctx
  local api_id = ctx.api.id

  local buf = _alf_buffers[api_id]
  
  if not buf then
    local err
    buf, err = Buffer.new(conf)
    if not buf then
      ngx.log(ngx.ERR, "could not create ALF buffer: ", err)
      return
    end
    _alf_buffers[api_id] = buf
  end

  local req_body, res_body
  if ctx.bufferhttp then
    req_body = ctx.bufferhttp.req_body
    res_body = ctx.bufferhttp.res_body
  end

  buf:add_entry(ngx, req_body, res_body,conf)
end

return BufferHTTPHandler
