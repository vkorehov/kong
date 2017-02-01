return {
  {
    name = "2017-01-30-121100_basicauth_consumer_id_idx",
    up = function(db, properties)
      return db:execute_command [[
        {"createIndexes":"basicauth_credentials","indexes":[{"key": {"consumer_id": 1},"name": "basicauth_consumer_id_idx","unique": false}]}
      ]]
    end,
    down = [[]]
  },
  {
    name = "2017-01-30-121100_basicauth_credentials_pkey",
    up = function(db, properties)
      return db:execute_command [[
        {"createIndexes":"basicauth_credentials","indexes":[{"key": {"id": 1},"name": "basicauth_credentials_pkey","unique": true}]}
      ]]
    end,
    down = [[]]
  },
  {
    name = "2017-01-30-121100_basicauth_username_idx",
    up = function(db, properties)
      return db:execute_command [[
        {"createIndexes":"basicauth_credentials","indexes":[{"key": {"username": 1},"name": "basicauth_username_idx","unique": false}]}
      ]]
    end,
    down = [[]]
  }
  
  
  
 }
  
  