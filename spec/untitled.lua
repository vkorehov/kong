local helpers = require "spec.helpers"
local cjson = require "cjson"

describe("plugin: request transformer", function()
  local client
  local api1, api2, api3, api4, api5, api6

  setup(function()
    helpers.dao:truncate_tables()
    helpers.execute "pkill nginx; pkill serf"
    assert(helpers.prepare_prefix())

    api1 = assert(helpers.dao.apis:insert {name = "tests-request-transformer-1", request_host = "test1.com", upstream_url = "http://mockbin.com"})
    api2 = assert(helpers.dao.apis:insert {name = "tests-request-transformer-2", request_host = "test2.com", upstream_url = "http://httpbin.org"})
    api3 = assert(helpers.dao.apis:insert {name = "tests-request-transformer-3", request_host = "test3.com", upstream_url = "http://mockbin.com"})
    api4 = assert(helpers.dao.apis:insert {name = "tests-request-transformer-4", request_host = "test4.com", upstream_url = "http://mockbin.com"})
    api5 = assert(helpers.dao.apis:insert {name = "tests-request-transformer-5", request_host = "test5.com", upstream_url = "http://mockbin.com"})
    api6 = assert(helpers.dao.apis:insert {name = "tests-request-transformer-6", request_host = "test6.com", upstream_url = "http://mockbin.com"})

    -- plugin config 1
    assert(helpers.dao.plugins:insert {
      api_id = api1.id,
      name = "request-transformer",
      config = {
        add = {
          headers = {"h1:v1", "h2:v2"},
          querystring = {"q1:v1"},
          body = {"p1:v1"}
        }
      }
    })
    -- plugin config 2
    assert(helpers.dao.plugins:insert {
      api_id = api2.id,
      name = "request-transformer",
      config = {
        add = {
          headers = {"host:mark"}
        }
      }
    })
    -- plugin config 3
    assert(helpers.dao.plugins:insert {
      api_id = api3.id,
      name = "request-transformer",
      config = {
        add = {
          headers = {"x-added:a1", "x-added2:b1", "x-added3:c2"},
          querystring = {"query-added:newvalue", "p1:a1"},
          body = {"newformparam:newvalue"}
        },
        remove = {
          headers = {"x-to-remove"},
          querystring = {"toremovequery"}
        },
        append = {
          headers = {"x-added:a2", "x-added:a3"},
          querystring = {"p1:a2", "p2:b1"}
        },
        replace = {
          headers = {"x-to-replace:false"},
          querystring = {"toreplacequery:no"}
        }
      }
    })
    -- plugin config 4
    assert(helpers.dao.plugins:insert {
      api_id = api4.id,
      name = "request-transformer",
      config = {
        remove = {
          headers = {"x-to-remove"},
          querystring = {"q1"},
          body = {"toremoveform"}
        }
      }
    })
    -- plugin config 5
    assert(helpers.dao.plugins:insert {
      api_id = api5.id,
      name = "request-transformer",
      config = {
        replace = {
          headers = {"h1:v1"},
          querystring = {"q1:v1"},
          body = {"p1:v1"}
        }
      }
    })
    -- plugin config 6
    assert(helpers.dao.plugins:insert {
      api_id = api6.id,
      name = "request-transformer",
      config = {
        append = {
          headers = {"h1:v1", "h1:v2", "h2:v1",},
          querystring = {"q1:v1", "q1:v2", "q2:v1"},
          body = {"p1:v1", "p1:v2", "p2:v1"}
        }
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

  describe("remove", function()
    it("specified header", function()
      local res = assert(client:send {
        method = "POST",
        path = "/request",
        query = {
          hello = "world",
          hello2 = "world2",
        },
        body = cjson.encode {
          ["toremoveform"] = "yes",
          ["nottoremove"] = "yes"
        },
        headers = {
          ["Content-Type"] = "application/json",
          host = "test4.com"
        }
      })
      local body = assert.response(res).has.status(200)
      local json = assert.request(res).has.jsonbody()
      assert.equal({},json)
      
      local param = assert.request(res).has.queryparam("hello2")
      assert.equal("world2", param)
      
      local param = assert.request(res).has.formparam("nottoremove")
      assert.equal("yes", param)
      
      local json = assert.has.jsonbody(res)
      assert.equal({},json)
      assert.has.no.header("x-to-remove", json)
      assert.has.header("x-another-header", json)
      
      local value = assert.response(res).has.header("x-to-remove")
      local value = assert.request(res).has.no.header("x-another-header")
      assert.equal("something", value)
    end)
  end)
end)
