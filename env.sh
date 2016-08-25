export OPENSSL_CONF=/root/kong/etc/openssl.cnf
export LUAROCKS_CONFIG=/root/kong/etc/luarocks/config-5.1.lua
export PATH="/root/kong/bin:$PATH:/root/kong/openresty/bin:/root/kong/openresty/nginx/sbin"
export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:/root/kong/lib:/root/kong/lua/5.1"
export LUA_CPATH="./?.so;/root/kong/lib/lua/5.1/?.so"
export LUA_PATH="./?.lua;/root/kong/share/lua/5.1/?.lua;/root/kong/share/lua/5.1/?/init.lua;/root/kong/share/luajit-2.1.0-beta2/?.lua"
