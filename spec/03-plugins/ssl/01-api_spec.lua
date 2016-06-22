local helpers = require "spec.helpers"
local cjson = require "cjson"
local ssl_fixtures = require "spec.03-plugins.ssl.fixtures"

describe("SSL Admin API", function()
  local admin_client
  setup(function()
    helpers.dao:truncate_tables()
    assert(helpers.prepare_prefix())
    
    assert(helpers.dao.apis:insert {name = "mockbin", request_host = "mockbin.com", upstream_url = "http://mockbin.com"})
    
    assert(helpers.start_kong())
    admin_client = assert(helpers.http_client("127.0.0.1", helpers.test_conf.admin_port))
  end)

  teardown(function()
    if admin_client then
      admin_client:close()
    end
    helpers.stop_kong()
  end)

  describe("/apis/:api/plugins", function()
    it("should refuse to set a `consumer_id` if asked to", function()
      local res = assert(admin_client:send {
        method = "POST",
        path = "/apis/mockbin/plugins/",
        body = {
          name = "ssl",
          consumer_id = "504b535e-dc1c-11e5-8554-b3852c1ec156",
          ["config.cert"] = ssl_fixtures.cert,
          ["config.key"] = ssl_fixtures.key
        },
        headers = {
          ["Content-Type"] = "multipart/form-data"
        }
      })
      local body = cjson.decode(assert.res_status(400, res))
      assert.equal("No consumer can be configured for that plugin", body.message)
    end)
  end)
end)
