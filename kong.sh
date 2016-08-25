#!/bin/bash

exec '/root/kong/bin/lua' -e 'local k,l,_=pcall(require,"luarocks.loader") _=k and l.add_context("kong","0.8.3-0")' '/root/kong/lib/luarocks/rocks/kong/0.8.3-0/bin/kong' "$@"
