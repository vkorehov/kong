package = "ipr"
version = "0.0.1-0"
supported_platforms = {"linux", "macosx"}
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
  "lua ~> 5.1"
}
build = {
  type = "builtin",
  modules = {
    ["kong.plugins.ldap-auth-optional.handler"] = "kong/plugins/ldap-auth-optional/handler.lua",
    ["kong.plugins.ldap-auth-optional.access"] = "kong/plugins/ldap-auth-optional/access.lua",
    ["kong.plugins.ldap-auth-optional.schema"] = "kong/plugins/ldap-auth-optional/schema.lua",
    ["kong.plugins.ldap-auth-optional.ldap"] = "kong/plugins/ldap-auth-optional/ldap.lua",
    ["kong.plugins.ldap-auth-optional.asn1"] = "kong/plugins/ldap-auth-optional/asn1.lua",

    ["kong.plugins.ssl-auth-optional.handler"] = "kong/plugins/ssl-auth-optional/handler.lua",
    ["kong.plugins.ssl-auth-optional.access"] = "kong/plugins/ssl-auth-optional/access.lua",
    ["kong.plugins.ssl-auth-optional.schema"] = "kong/plugins/ssl-auth-optional/schema.lua",

    ["kong.plugins.composite-auth.handler"] = "kong/plugins/composite-auth/handler.lua",
    ["kong.plugins.composite-auth.access"] = "kong/plugins/composite-auth/access.lua",
    ["kong.plugins.composite-auth.schema"] = "kong/plugins/composite-auth/schema.lua",
  }
}
