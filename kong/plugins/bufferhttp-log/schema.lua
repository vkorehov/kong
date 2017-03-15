return {
  fields = {
    retry_count = {type = "number", default = 10},
    queue_size = {type = "number", default = 1000},
    queue_size_mb = {type = "number", default = 20},
    max_msg_size_mb = {type = "number", default = 2},
    max_sending_queue_size_mb = {type = "number", default = 200},
    flush_timeout = {type = "number", default = 2},
    log_request = {type = "boolean", default = false},
    log_response = {type = "boolean", default = false},
    log_oauth2_response = {type = "boolean", default = false},
    connection_timeout = {type = "number", default = 30},
    endpoint = {type = "string", required = true, default = "http://localhost/api/event"},
    https_verify = {type = "boolean", default = false},
    secure_message = {type = "boolean", default = false},
    add_request_id = {type = "boolean", default = true},
    secure_patterns = {type = "array", default = { "([Pp]assword\":)\"(.-)\"", "([Tt]oken\":)\"(.-)\""}},
    default_auth_key = {type = "string", default = "default dm auth key"},
    default_app = {type = "string", default = "default dm app"}
  }
}
