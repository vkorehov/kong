local helpers = require "spec.helpers"
local cjson = require "cjson"
local base64 = require "base64"
local cache = require "kong.tools.database_cache"

-- Note: these tests use an external ldap test server.
-- see: http://www.forumsys.com/en/tutorials/integration-how-to/ldap/online-ldap-test-server/

local PROXY_URL = helpers.PROXY_URL
local API_URL = helpers.API_URL

describe("Plugin: ldap-auth", function()
  
  local client
  
  setup(function()
    helpers.dao:truncate_tables()
    assert(helpers.prepare_prefix())

    local api1 = assert(helpers.dao.apis:insert {
      name = "test-ldap",
      request_host = "ldap.com",
      upstream_url = "http://mockbin.com"
    })
    local api2 = assert(helpers.dao.apis:insert {
      name = "test-ldap2",
      request_host = "ldap2.com",
      upstream_url = "http://mockbin.com"
    })

    -- plugin 1
    assert(helpers.dao.plugins:insert {
      api_id = api1.id,
      name = "ldap-auth",
      config = {
        ldap_host = "ldap.forumsys.com", 
        ldap_port = "389", 
        start_tls = false, 
        base_dn = "dc=example,dc=com", 
        attribute = "uid"
      }
    })
    -- plugin 2
    assert(helpers.dao.plugins:insert {
      api_id = api2.id,
      name = "ldap-auth",
      config = {
        ldap_host = "ldap.forumsys.com", 
        ldap_port = "389", 
        start_tls = false, 
        base_dn = "dc=example,dc=com", 
        attribute = "uid", 
        hide_credentials = true
      }
    })
  
    assert(helpers.start_kong())
  end)
  
  teardown(function()
    helpers.stop_kong()
  end)

  before_each(function()
    client = assert(helpers.http_client("127.0.0.1", helpers.proxy_port))
  end)

  after_each(function()
    if client then client:close() end
  end)
  
  it("returns 'invalid credentials' and www-authenticate header when the credential is missing", function()
    local r = assert(client:send {
      method = "GET",
      path = "/get", 
      headers = {
        host = "ldap.com"
      }
    })
    local body = assert.response(r).has.status(401)
    local value = assert.response(r).has.header("www-authenticate")
    assert.are.equal('LDAP realm="kong"', value)
    local json = assert.response(r).has.jsonbody()
    assert.equal("Unauthorized", json.message)
  end)
  it("returns 'invalid credentials' when credential value is in wrong format in authorization header", function()
    local r = assert(client:send {
      method = "GET",
      path = "/get",
      headers = {
        host = "ldap.com", 
        authorization = "abcd"
      }
    })
    assert.response(r).has.status(403)
    local json = assert.response(r).has.jsonbody()
    assert.equal("Invalid authentication credentials", json.message)
  end)
  it("returns 'invalid credentials' when credential value is in wrong format in proxy-authorization header", function()
    local r = assert(client:send {
      method = "GET",
      path = "/get", 
      headers = {
        host = "ldap.com", 
        ["proxy-authorization"] = "abcd"
      }
    })
    assert.response(r).has.status(403)
    local json = assert.response(r).has.jsonbody()
    assert.equal("Invalid authentication credentials", json.message)
  end)

  it("returns 'invalid credentials' when credential value is missing in authorization header", function()
    local r = assert(client:send {
      method = "GET",
      path = "/get", 
      headers = {
        host = "ldap.com", 
        authorization = "ldap "
      }
    })
    assert.response(r).has.status(403)
    local json = assert.response(r).has.jsonbody()
    assert.equal("Invalid authentication credentials", json.message)
  end)

--local _, status = http_client.post(PROXY_URL.."/request", {}, {host = "ldap.com", authorization = "ldap "..base64.encode("einstein:password")})

  it("#only passes if credential is valid in post request", function()
    local r = assert(client:send {
      method = "POST",
      path = "/request",
      body = {},
      headers = {
        host = "ldap.com", 
        authorization = "ldap "..base64.encode("einstein:password"),
        ["content-type"] = "application/x-www-form-urlencoded",
      }
    })
    assert.response(r).has.status(200)
  end)

  it("should pass if credential is valid and starts with space in post request", function()
    local r = assert(client:send {
      method = "POST",
      path = "/request", 
      headers = {
        host = "ldap.com", 
        authorization = " ldap "..base64.encode("einstein:password")
      }
    })
    assert.response(r).has.status(200)
  end)

  it("should pass if signature type indicator is in caps and credential is valid in post request", function()
    local r = assert(client:send {
      method = "POST",
      path = "/request", 
      headers = {
        host = "ldap.com", 
        authorization = "LDAP "..base64.encode("einstein:password")
      }
    })
    assert.response(r).has.status(200)
  end)

  it("should pass if credential is valid in get request", function()
    local r = assert(client:send {
      method = "GET",
      path = "/request", 
      headers = {
        host = "ldap.com", 
        authorization = "ldap "..base64.encode("einstein:password")
      }
    })
    assert.response(r).has.status(200)
    local value = assert.response(r).has.header("x-credential-username")
    assert.are.equal("einstein", value)
    
    local parsed_response = cjson.decode(response)
    assert.truthy(parsed_response.headers["x-credential-username"])
    assert.equal("einstein", parsed_response.headers["x-credential-username"])
  end)

  it("should not pass if credential does not has password encoded in get request", function()
    local _, status = http_client.get(PROXY_URL.."/request", {}, {host = "ldap.com", authorization = "ldap "..base64.encode("einstein:")})
    assert.equal(403, status)
  end)

  it("should not pass if credential has multiple encoded username or password separated by ':' in get request", function()
    local _, status = http_client.get(PROXY_URL.."/request", {}, {host = "ldap.com", authorization = "ldap "..base64.encode("einstein:password:another_password")})
    assert.equal(403, status)
  end)

  it("should not pass if credential is invalid in get request", function()
    local _, status = http_client.get(PROXY_URL.."/request", {}, {host = "ldap.com", authorization = "ldap "..base64.encode("einstein:wrong_password")})
    assert.equal(403, status)
  end)
  
  it("should not hide credential sent along with authorization header to upstream server", function()
    local response, status = http_client.get(PROXY_URL.."/request", {}, {host = "ldap.com", authorization = "ldap "..base64.encode("einstein:password")})
    assert.equal(200, status)
    local parsed_response = cjson.decode(response)
    assert.equal("ldap "..base64.encode("einstein:password"), parsed_response.headers["authorization"])
  end)
  
  it("should hide credential sent along with authorization header to upstream server", function()
    local response, status = http_client.get(PROXY_URL.."/request", {}, {host = "ldap2.com", authorization = "ldap "..base64.encode("einstein:password")})
    assert.equal(200, status)
    local parsed_response = cjson.decode(response)
    assert.falsy(parsed_response.headers["authorization"])
  end)
  
  it("should cache LDAP Auth Credential", function()
    local _, status = http_client.get(PROXY_URL.."/request", {}, {host = "ldap.com", authorization = "ldap "..base64.encode("einstein:password")})
    assert.equals(200, status)
          
    -- Check that cache is populated
    local cache_key = cache.ldap_credential_key("einstein")
    local exists = true
    while(exists) do
      local _, status = http_client.get(API_URL.."/cache/"..cache_key)
      if status ~= 200 then
        exists = false
      end
    end
    assert.equals(200, status)
  end)
end)
