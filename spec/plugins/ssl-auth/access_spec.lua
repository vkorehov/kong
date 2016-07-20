local spec_helper = require "spec.spec_helpers"
local http_client = require "kong.tools.http_client"

local STUB_GET_URL = spec_helper.STUB_GET_URL
local STUB_POST_URL = spec_helper.STUB_POST_URL

describe("SSLAuth Plugin", function()

  setup(function()
    spec_helper.prepare_db()
    spec_helper.insert_fixtures {
      api = {
        {name = "tests sslauth 1", public_dns = "sslauth1.com", target_url = "http://mockbin.com"},
        {name = "tests sslauth 2", public_dns = "sslauth2.com", target_url = "http://mockbin.com"}
      },
      consumer = {
      },
      plugin_configuration = {
        {name = "ssl-auth", value = {say_hello = true }, __api = 1},
        {name = "ssl-auth", value = {say_hello = false }, __api = 2},
      }
    }

    spec_helper.start_kong()
  end)

  teardown(function()
    spec_helper.stop_kong()
  end)

  describe("Response", function()
     it("should return an Hello-World header with Hello World!!! value when say_hello is true", function()
      local _, status, headers = http_client.get(STUB_GET_URL, {}, {host = "sslauth1.com"})
      assert.are.equal(200, status)
      assert.are.same("Hello World!!!", headers["hello-world"])
    end)

    it("should return an Hello-World header with Bye World!!! value when say_hello is false", function()
      local _, status, headers = http_client.get(STUB_GET_URL, {}, {host = "sslauth2.com"})
      assert.are.equal(200, status)
      assert.are.same("Bye World!!!", headers["hello-world"])
    end)
  end)
end)
