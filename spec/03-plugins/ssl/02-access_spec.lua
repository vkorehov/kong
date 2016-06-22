local helpers = require "spec.helpers"
local cjson = require "cjson"
local url = require "socket.url"
local pl_dir = require "pl.dir"
local pl_path = require "pl.path"
local ssl_fixtures = require "spec.03-plugins.ssl.fixtures"

local STUB_GET_SSL_URL = "https://localhost:"..helpers.test_conf.proxy_ssl_port
local API_URL = "http://localhost:"..helpers.test_conf.admin_port

describe("SSL Plugin", function()
  local proxy_client, admin_client, proxy_ssl_client
  
  setup(function()
    helpers.dao:truncate_tables()
    assert(helpers.prepare_prefix())
    
    assert(helpers.dao.apis:insert {request_host = "ssl1.com", upstream_url = "http://mockbin.com"})
    assert(helpers.dao.apis:insert {request_host = "ssl2.com", upstream_url = "http://mockbin.com"})
    assert(helpers.dao.apis:insert {request_host = "ssl3.com", upstream_url = "http://mockbin.com"})
    assert(helpers.dao.apis:insert {request_host = "ssl4.com", upstream_url = "http://mockbin.com"})
    
    assert(helpers.start_kong())
    proxy_client = assert(helpers.http_client("127.0.0.1", helpers.test_conf.proxy_port))
    proxy_ssl_client = assert(helpers.http_client("127.0.0.1", helpers.test_conf.proxy_ssl_port))
    admin_client = assert(helpers.http_client("127.0.0.1", helpers.test_conf.admin_port))

    -- The SSL plugin needs to be added manually because we are requiring ngx.ssl
    local res = assert(admin_client:send {
      method = "POST",
      path = "/apis/ssl1.com/plugins",
      body = {
        ["name"] = "ssl", 
        ["config.cert"] = ssl_fixtures.cert, 
        ["config.key"] = ssl_fixtures.key
      },
      headers = {
        ["Content-Type"] = "multipart/form-data"
      }
    })
    assert.res_status(201, res)
    
    res = assert(admin_client:send {
      method = "POST",
      path = "/apis/ssl2.com/plugins/",
      body = {
        name = "ssl", 
        ["config.cert"] = ssl_fixtures.cert, 
        ["config.key"] = ssl_fixtures.key,
        ["config.only_https"] = true
      },
      headers = {
        ["Content-Type"] = "multipart/form-data"
      }
    })
    assert.res_status(201, res)
    
    res = assert(admin_client:send {
      method = "POST",
      path = "/apis/ssl4.com/plugins/",
      body = {
        name = "ssl", 
        ["config.cert"] = ssl_fixtures.cert, 
        ["config.key"] = ssl_fixtures.key,
        ["config.only_https"] = true,
        ["config.accept_http_if_already_terminated"] = true
      },
      headers = {
        ["Content-Type"] = "multipart/form-data"
      }
    })
    assert.res_status(201, res)
  end)

  teardown(function()
    if proxy_client then
      proxy_client:close()
    end
    if admin_client then
      admin_client:close()
    end
    if proxy_ssl_client then
      proxy_ssl_client:close()
    end
    helpers.stop_kong()
  end)

  describe("SSL conversions", function()
    it("should not convert an invalid cert to DER #o", function()
      local res = assert(admin_client:send {
        method = "POST",
        path = "/apis/ssl1.com/plugins/",
        body = {
          name = "ssl",
          ["config.cert"] = "asd",
          ["config.key"] = ssl_fixtures.key
        },
        headers = {
          ["Content-Type"] = "multipart/form-data"
        }
      })
      local body = cjson.decode(assert.res_status(400, res))
      assert.equals("Invalid SSL certificate", body["config.cert"])
    end)
    it("should not convert an invalid key to DER", function()
      local res = assert(admin_client:send {
        method = "POST",
        path = "/apis/ssl1.com/plugins/",
        body = {
          name = "ssl", 
          ["config.cert"] = ssl_fixtures.cert, 
          ["config.key"] = "hello"
        },
        headers = {
          ["Content-Type"] = "multipart/form-data"
        }
      })
      local body = cjson.decode(assert.res_status(400, res))
      assert.equals("Invalid SSL certificate key", body["config.key"])
    end)
  end)

  
  describe("SSL Resolution", function()
    it("should return default CERTIFICATE when requesting other APIs", function()
      local parsed_url = url.parse(STUB_GET_SSL_URL)
      local ok, res, output = helpers.execute("(echo \"GET /\"; sleep 2) | openssl s_client -connect "..parsed_url.host..":"..tostring(parsed_url.port).." -servername test4.com")
      
      assert.truthy(output:match("US/ST=California/L=San Francisco/O=Kong/OU=IT Department/CN=localhost"))
    end)

    it("should work when requesting a specific API", function()
      local parsed_url = url.parse(STUB_GET_SSL_URL)
      local ok, res, output = helpers.execute("(echo \"GET /\"; sleep 2) | openssl s_client -connect "..parsed_url.host..":"..tostring(parsed_url.port).." -servername ssl1.com")
      assert.truthy(ok)
      assert.truthy(output:match("US/ST=California/L=San Francisco/O=Kong/OU=IT/CN=ssl1.com"))
    end)

  end)

  describe("only_https", function()
    it("should block request without https", function()
      local res = assert(proxy_client:send {
        method = "GET",
        path = "/request",
        headers = {
          ["Host"] = "ssl2.com"
        }
      })
      local body = cjson.decode(assert.res_status(426, res))
      assert.are.same("Please use HTTPS protocol", body.message)
      assert.are.same("TLS/1.0, HTTP/1.1", res.headers.upgrade)
      assert.are.same("close, Upgrade", res.headers.connection)
    end)

    it("should not block request with https", function()
      local res = assert(proxy_ssl_client:send {
        method = "GET",
        path = "/request",
        headers = {
          ["Host"] = "ssl2.com"
        }
      })
      assert.res_status(200, res)
    end)

    it("should block request with https in x-forwarded-proto but no accept_if_already_terminated", function()
      local res = assert(proxy_client:send {
        method = "GET",
        path = "/request",
        headers = {
          ["Host"] = "ssl2.com",
          ["x-forwarded-proto"] = "https"
        }
      })
      assert.res_status(426, res)
    end)

    it("should not block request with https", function()
      local res = assert(proxy_client:send {
        method = "GET",
        path = "/request",
        headers = {
          ["Host"] = "ssl4.com",
          ["x-forwarded-proto"] = "https"
        }
      })
      assert.res_status(200, res)
    end)

    it("should not block request with https in x-forwarded-proto but accept_if_already_terminated", function()
      local res = assert(proxy_client:send {
        method = "GET",
        path = "/request",
        headers = {
          ["Host"] = "ssl4.com",
          ["x-forwarded-proto"] = "https"
        }
      })
      assert.res_status(200, res)
    end)
  end)

  describe("should work with curl #o", function()
    local res = assert(admin_client:send {
      method = "GET",
      path = "/apis",
      headers = {
        ["Host"] = "ssl3.com"
      }
    })
    local body = cjson.decode(assert.res_status(200, res))
    local api_id = body.data[1].id
    local kong_working_dir = helpers.test_conf.prefix
    
    local ssl_cert_path = pl_path.join(kong_working_dir, "ssl", "kong-default.crt")
    local ssl_key_path = pl_path.join(kong_working_dir, "ssl", "kong-default.key")
    local ok, res, output = helpers.execute("curl -s -o /dev/null -w \"%{http_code}\" "..API_URL.."/apis/"..api_id.."/plugins/ --form \"name=ssl\" --form \"config.cert=@"..ssl_cert_path.."\" --form \"config.key=@"..ssl_key_path.."\"")
    assert.are.equal(201, tonumber(output))
  end)
  
end)
