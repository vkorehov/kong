package = "plugin"
version = "0.0.1-0"
supported_platforms = {"linux", "macosx", "mingw32"}
source = {
  url = "git://github.com/vkorehov/kong",
  tag = "next"
}
description = {
  summary = "Idea Port Riga specific kong plugins",
  homepage = "http://ideaportriga.lv",
  license = "MIT"
}
dependencies = {
  "luasec == 0.6-3",
  "luasocket == 2.0.2",
  "penlight == 1.3.2",
  "mediator_lua == 1.1.2",
  "lua-resty-http == 0.08",
  "lua-resty-jit-uuid == 0.0.4",
  "multipart == 0.3",
  "version == 0.2",
  "lapis == 1.5.1",
  "lua-cassandra == 0.5.3",
  "pgmoon == 1.7.0",
  "luatz == 0.3",
  "lua_system_constants == 0.1.2-0",
  "lua-resty-iputils == 0.2.1",
  "luacrypto == 0.3.3-0",
  "luasyslog == 1.0.1-0",
  "lua_pack == 1.0.4"
}
build = {
  type = "builtin",
  modules = {
    ["consulclient"] = "kong/consulclient.lua",

    ["kong.plugins.bufferhttp-log.handler"] = "kong/plugins/bufferhttp-log/handler.lua",
    ["kong.plugins.bufferhttp-log.schema"] = "kong/plugins/bufferhttp-log/schema.lua",
    ["kong.plugins.bufferhttp-log.buffer"] = "kong/plugins/bufferhttp-log/buffer.lua",
    ["kong.plugins.bufferhttp-log.alf"] = "kong/plugins/bufferhttp-log/alf.lua",
  }
}
