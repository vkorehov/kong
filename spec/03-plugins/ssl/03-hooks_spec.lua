local helpers = require "spec.helpers"
local cjson = require "cjson"
local cache = require "kong.tools.database_cache"
local ssl_fixtures = require "spec.03-plugins.ssl.fixtures"
local IO = require "kong.tools.io"
local url = require "socket.url"

local STUB_GET_SSL_URL = "https://localhost:"..helpers.test_conf.proxy_ssl_port
local API_URL = "http://localhost:"..helpers.test_conf.admin_port

describe("SSL Hooks", function()
  local admin_client
  setup(function()
    assert(helpers.prepare_prefix())
    assert(helpers.start_kong())
    proxy_ssl_client = assert(helpers.http_client("127.0.0.1", helpers.test_conf.proxy_ssl_port))
    admin_client = assert(helpers.http_client("127.0.0.1", helpers.test_conf.admin_port))
  end)

  teardown(function()
    if admin_client then
      admin_client:close()
    end
    helpers.stop_kong()
  end)

  before_each(function()
    helpers.dao:truncate_tables()
    
    assert(helpers.dao.apis:insert {request_host = "ssl1.com", upstream_url = "http://mockbin.com"})
     
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
  end)

  describe("SSL plugin entity invalidation", function()
    it("should invalidate when SSL plugin is deleted", function()
      -- It should work
      local parsed_url = url.parse(STUB_GET_SSL_URL)
      local ok, res, output = helpers.execute("(echo \"GET /\"; sleep 2) | openssl s_client -connect "..parsed_url.host..":"..tostring(parsed_url.port).." -servername ssl1.com")

      assert.truthy(output:match("US/ST=California/L=San Francisco/O=Kong/OU=IT/CN=ssl1.com"))

      -- Check that cache is populated
      local res = assert(admin_client:send {
        method = "GET",
        path = "/apis",
        headers = {
          ["Host"] = "ssl1.com"
        }
      })
      local body = cjson.decode(assert.res_status(200, res))
      local api_id = body.data[1].id
      assert.truthy(api_id)

      local cache_key = cache.ssl_data(api_id)
      local res = assert(admin_client:send {
        method = "GET",
        path = "/cache/"..cache_key,
      })
      assert.res_status(200, res)

      -- Retrieve SSL plugin
      local res = assert(admin_client:send {
        method = "GET",
        path = "/plugins/",
        body = {
          api_id=api_id, 
          name="ssl"
        }
      })
      local body = cjson.decode(assert.res_status(200, res))
      local plugin_id = body.data[1].id
      assert.truthy(plugin_id)

      -- Delete SSL plugin (which triggers invalidation)
      local res = assert(admin_client:send {
        method = "DELETE",
        path = "/plugins/"..plugin_id,
      })
      assert.res_status(204, res)

      -- Wait for cache to be invalidated
      helpers.wait_until(function()
        local res = assert(admin_client:send {
          method = "GET",
          path = "/cache/"..cache_key
        })
        res:read_body()
        return res.status == 404
      end)

      -- It should not work
      local parsed_url = url.parse(STUB_GET_SSL_URL)
      local ok, res, output = helpers.execute("(echo \"GET /\"; sleep 2) | openssl s_client -connect "..parsed_url.host..":"..tostring(parsed_url.port).." -servername ssl1.com")

      assert.falsy(output:match("US/ST=California/L=San Francisco/O=Kong/OU=IT/CN=ssl1.com"))
    end)
    it("should invalidate when Basic Auth Credential entity is updated", function()
      -- It should work
      local parsed_url = url.parse(STUB_GET_SSL_URL)
      local ok, res, output = helpers.execute("(echo \"GET /\"; sleep 2) | openssl s_client -connect "..parsed_url.host..":"..tostring(parsed_url.port).." -servername ssl1.com")

      assert.truthy(output:match("US/ST=California/L=San Francisco/O=Kong/OU=IT/CN=ssl1.com"))

      -- Check that cache is populated
      local res = assert(admin_client:send {
        method = "GET",
        path = "/apis",
        headers = {
          ["Host"] = "ssl1.com"
        }
      })
      local body = cjson.decode(assert.res_status(200, res))
      local api_id = body.data[1].id
      assert.truthy(api_id)

      local cache_key = cache.ssl_data(api_id)
      local res = assert(admin_client:send {
        method = "GET",
        path = "/cache/"..cache_key,
      })
      assert.res_status(200, res)

      -- Retrieve SSL plugin
      local res = assert(admin_client:send {
        method = "GET",
        path = "/plugins/",
        body = {
          api_id=api_id, 
          name="ssl"
        }
      })
      local body = cjson.decode(assert.res_status(200, res))
      local plugin_id = body.data[1].id
      assert.truthy(plugin_id)
      
      -- Update SSL plugin (which triggers invalidation)
      local kong_working_dir = helpers.test_conf.prefix
      local ssl_cert_path = IO.path:join(kong_working_dir, "ssl", "kong-default.crt")
      local ssl_key_path = IO.path:join(kong_working_dir, "ssl", "kong-default.key")

      local ok, res, output = helpers.execute("curl -X PATCH -s -o /dev/null -w \"%{http_code}\" "..API_URL.."/apis/"..api_id.."/plugins/"..plugin_id.." --form \"config.cert=@"..ssl_cert_path.."\" --form \"config.key=@"..ssl_key_path.."\"")
      assert.are.equal(200, tonumber(output))

      -- Wait for cache to be invalidated
      helpers.wait_until(function()
        local res = assert(admin_client:send {
          method = "GET",
          path = "/cache/"..cache_key
        })
        res:read_body()
        return res.status == 404
      end)

      -- It should not work
      local parsed_url = url.parse(STUB_GET_SSL_URL)
      local ok, res, output = helpers.execute("(echo \"GET /\"; sleep 2) | openssl s_client -connect "..parsed_url.host..":"..tostring(parsed_url.port).." -servername ssl1.com")

      assert.falsy(output:match("US/ST=California/L=San Francisco/O=Kong/OU=IT/CN=ssl1.com"))
      assert.truthy(output:match("US/ST=California/L=San Francisco/O=Kong/OU=IT Department/CN=localhost"))
    end)
  end)

  describe("API entity invalidation", function()
    it("should invalidate when API entity is deleted", function()
      -- It should work
      local parsed_url = url.parse(STUB_GET_SSL_URL)
      local ok, res, output = helpers.execute("(echo \"GET /\"; sleep 2) | openssl s_client -connect "..parsed_url.host..":"..tostring(parsed_url.port).." -servername ssl1.com")

      assert.truthy(res:output("US/ST=California/L=San Francisco/O=Kong/OU=IT/CN=ssl1.com"))

       -- Check that cache is populated
      local res = assert(admin_client:send {
        method = "GET",
        path = "/apis",
        headers = {
          ["Host"] = "ssl1.com"
        }
      })
      local body = cjson.decode(assert.res_status(200, res))
      local api_id = body.data[1].id
      assert.truthy(api_id)
      
      local cache_key = cache.ssl_data(api_id)
      local res = assert(admin_client:send {
        method = "GET",
        path = "/cache/"..cache_key,
      })
      assert.res_status(200, res)
      
      -- Delete API (which triggers invalidation)
      local res = assert(admin_client:send {
        method = "DELETE",
        path = "/apis/"..api_id,
      })
      assert.res_status(204, res)

      -- Wait for cache to be invalidated
      helpers.wait_until(function()
        local res = assert(admin_client:send {
          method = "GET",
          path = "/cache/"..cache_key
        })
        res:read_body()
        return res.status == 404
      end)

      -- It should not work
      local parsed_url = url.parse(STUB_GET_SSL_URL)
      local ok, res, output = helpers.execute("(echo \"GET /\"; sleep 2) | openssl s_client -connect "..parsed_url.host..":"..tostring(parsed_url.port).." -servername ssl1.com")

      assert.falsy(output:match("US/ST=California/L=San Francisco/O=Kong/OU=IT/CN=ssl1.com"))
    end) 
  end)
end)
