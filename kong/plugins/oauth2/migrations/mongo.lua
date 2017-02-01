return {
  {
    name = "2017-01-30-121100_oauth2_accesstoken_idx",
    up = function(db, properties)
      return db:execute_command [[
        {"createIndexes":"oauth2_tokens","indexes":[{"key": {"access_token": 1},"name": "oauth2_accesstoken_idx","unique": true}]}
      ]]
    end,
    down = [[]]
  },
  {
    name = "2017-01-30-121100_oauth2_token_refresh_idx",
    up = function(db, properties)
      return db:execute_command [[
        {"createIndexes":"oauth2_tokens","indexes":[{"key": {"refresh_token": 1},"name": "oauth2_token_refresh_idx","unique": true}]}
      ]]
    end,
    down = [[]]
  },
  {
    name = "2017-01-30-121100_oauth2_token_userid_idx",
    up = function(db, properties)
      return db:execute_command [[
        {"createIndexes":"oauth2_tokens","indexes":[{"key": {"authenticated_userid": 1},"name": "oauth2_token_userid_idx","unique": false}]}
      ]]
    end,
    down = [[]]
  },
  {
    name = "2017-01-30-121100_oauth2_tokens_pkey",
    up = function(db, properties)
      return db:execute_command [[
        {"createIndexes":"oauth2_tokens","indexes":[{"key": {"id": 1},"name": "oauth2_tokens_pkey","unique": true}]}
      ]]
    end,
    down = [[]]
  },
  {
    name = "2017-01-30-121100_oauth2_credentials_client_id_idx",
    up = function(db, properties)
      return db:execute_command [[
        {"createIndexes":"oauth2_credentials","indexes":[{"key": {"client_id": 1},"name": "oauth2_credentials_client_id_idx","unique": true}]}
      ]]
    end,
    down = [[]]
  },
  {
    name = "2017-01-30-121100_oauth2_credentials_secret_idx",
    up = function(db, properties)
      return db:execute_command [[
        {"createIndexes":"oauth2_credentials","indexes":[{"key": {"client_secret": 1},"name": "oauth2_credentials_secret_idx","unique": true}]}
      ]]
    end,
    down = [[]]
  },
  {
    name = "2017-01-30-121100_oauth2_credentials_pkey",
    up = function(db, properties)
      return db:execute_command [[
        {"createIndexes":"oauth2_credentials","indexes":[{"key": {"id": 1},"name": "oauth2_credentials_pkey","unique": true}]}
      ]]
    end,
    down = [[]]
  },
  {
    name = "2017-01-30-121100_oauth2_credentials_consumer_idx",
    up = function(db, properties)
      return db:execute_command [[
        {"createIndexes":"oauth2_credentials","indexes":[{"key": {"consumer_id": 1},"name": "oauth2_credentials_consumer_idx","unique": false}]}
      ]]
    end,
    down = [[]]
  },
  {
    name = "2017-01-30-121100_oauth2_autorization_code_idx",
    up = function(db, properties)
      return db:execute_command [[
        {"createIndexes":"oauth2_authorization_codes","indexes":[{"key": {"code": 1},"name": "oauth2_autorization_code_idx","unique": true}]}
      ]]
    end,
    down = [[]]
  },
  {
    name = "2017-01-30-121100_oauth2_authorization_codes_pkey",
    up = function(db, properties)
      return db:execute_command [[
        {"createIndexes":"oauth2_authorization_codes","indexes":[{"key": {"id": 1},"name": "oauth2_authorization_codes_pkey","unique": true}]}
      ]]
    end,
    down = [[]]
  },
  {
    name = "2017-01-30-121100_oauth2_authorization_userid_idx",
    up = function(db, properties)
      return db:execute_command [[
        {"createIndexes":"oauth2_authorization_codes","indexes":[{"key": {"authenticated_userid": 1},"name": "oauth2_authorization_userid_idx","unique": false}]}
      ]]
    end,
    down = [[]]
  }
 }
  
  