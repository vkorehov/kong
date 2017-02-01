return {
  --consumers
  {
    name = "2017-01-30-121100_consumers_pkey",
    up = function(db, properties)
      return db:execute_command [[
        {"createIndexes":"consumers","indexes":[{"key": {"id": 1},"name": "consumers_pkey","unique": true}]}
      ]]
    end,
    down = [[]]
  },
  {
    name = "2017-01-30-121100_consumers_username_idx",
    up = function(db, properties)
      return db:execute_command [[
        {"createIndexes":"consumers","indexes":[{"key": {"username": 1},"name": "consumers_username_idx","unique": false}]}
      ]]
    end,
    down = [[]]
  },
  {
    name = "2017-01-30-121100_custom_id_idx",
    up = function(db, properties)
      return db:execute_command [[
        {"createIndexes":"consumers","indexes":[{"key": {"custom_id": 1},"name": "custom_id_idx","unique": false}]}
      ]]
    end,
    down = [[]]
  },
  --apis
  {
    name = "2017-01-30-121100_api_idx",
    up = function(db, properties)
      return db:execute_command [[
        {"createIndexes":"apis","indexes":[{"key": {"id": 1},"name": "apis_id_idx","unique": true}]}
      ]]
    end,
    down = [[]]
  },
  {
    name = "2017-01-30-121100_api_name_idx",
    up = function(db, properties)
      return db:execute_command [[
        {"createIndexes":"apis","indexes":[{"key": {"name": 1},"name": "apis_name_idx","unique": true}]}
      ]]
    end,
    down = [[]]
  },
  {
    name = "2017-01-30-121100_api_req_path_idx",
    up = function(db, properties)
      return db:execute_command [[
        {"createIndexes":"apis","indexes":[{"key": {"request_path": 1},"name": "apis_request_path_idx","unique": true}]}
      ]]
    end,
    down = [[]]
  },
  -- acls
  {
    name = "2017-01-30-121100_acls_consumer_id",
    up = function(db, properties)
      return db:execute_command [[
        {"createIndexes":"acls","indexes":[{"key": {"consumer_id": 1},"name": "acls_consumer_id","unique": false}]}
      ]]
    end,
    down = [[]]
  },
  {
    name = "2017-01-30-121100_acls_group",
    up = function(db, properties)
      return db:execute_command [[
        {"createIndexes":"acls","indexes":[{"key": {"group": 1},"name": "acls_group","unique": false}]}
      ]]
    end,
    down = [[]]
  },
  {
    name = "2017-01-30-121100_acls_pkey",
    up = function(db, properties)
      return db:execute_command [[
        {"createIndexes":"acls","indexes":[{"key": {"id": 1},"name": "acls_pkey","unique": false}]}
      ]]
    end,
    down = [[]]
  },
  -- nodes
  {
    name = "2017-01-30-121100_nodes_pkey",
    up = function(db, properties)
      return db:execute_command [[
        {"createIndexes":"nodes","indexes":[{"key": {"name": 1},"name": "nodes_pkey","unique": true}]}
      ]]
    end,
    down = [[]]
  },
  {
    name = "2017-01-30-121100_nodes_cluster_listening_address_idx",
    up = function(db, properties)
      return db:execute_command [[
        {"createIndexes":"nodes","indexes":[{"key": {"cluster_listening_address": 1},"name": "nodes_cluster_listening_address_idx","unique": false}]}
      ]]
    end,
    down = [[]]
  },
  -- plugins
  {
    name = "2017-01-30-121100_plugins_api_idx",
    up = function(db, properties)
      return db:execute_command [[
        {"createIndexes":"plugins","indexes":[{"key": {"api_id": 1},"name": "plugins_api_idx","unique": false}]}
      ]]
    end,
    down = [[]]
  },
  {
    name = "2017-01-30-121100_plugins_consumer_idx",
    up = function(db, properties)
      return db:execute_command [[
        {"createIndexes":"plugins","indexes":[{"key": {"consumer_id": 1},"name": "plugins_consumer_idx","unique": false}]}
      ]]
    end,
    down = [[]]
  },
  {
    name = "2017-01-30-121100_plugins_name_idx",
    up = function(db, properties)
      return db:execute_command [[
        {"createIndexes":"plugins","indexes":[{"key": {"name": 1,"id": 1},"name": "plugins_name_idx","unique": true}]}
      ]]
    end,
    down = [[]]
  },
  --ttls
  {
    name = "2017-01-30-121100_ttls_pkey",
    up = function(db, properties)
      return db:execute_command [[
        {"createIndexes":"ttls","indexes":[{"key": {"primary_key_value": 1,"collection_name": 1},"name": "ttls_pkey","unique": true}]}
      ]]
    end,
    down = [[]]
  }
 }
  
  