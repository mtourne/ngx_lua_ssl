-- Copyright (C) 2016 Matthieu Tourne

-- part of lua-resty-core, ships with OpenResty
local ssl = require("ngx.ssl")
-- part of OpenResty, could be swapped with cmsgpack
local cjson = require("cjson")
-- submodule in lua/libs
local shcache = require("libs/shcache/shcache")


local CERT_DIRECTORY = 'conf/certs/'

local function load_cert_from_cache(name)
   local lookup = function ()
      -- load from disk as a demo. You should probably load it
      -- from a local redis / memc

      -- load cert
      local f, err = io.open(CERT_DIRECTORY .. name .. '.pem')
      if not f then
         return nil, err
      end

      local cert = f:read()

      f:close()

      -- load key
      local f, err = io.open(CERT_DIRECTORY .. name .. '.key')
      if not f then
         return nil, err
      end

      local key = f:read()

      f:close()

      return {
         cert = cert,
         key = key,
      }
   end

   local cert_cache_table, err = shcache:new(
        ngx.shared.cert_cache,
        { external_lookup = lookup,
          encode = cjson.encode,
          decode = cjson.decode
        },
        { positive_ttl = 300,   -- cache successful lookup (in secs)
          negative_ttl = 300,   -- cache failed lookup (in secs)
          name = 'cert_cache',  -- "named" cache, useful for debug / report
        }
   )

   if not cert_cache_table then
      ngx.log(ngx.ERR, "failed to init cache table: ", err)
      return ngx.exit(ngx.ERROR)
   end

   -- load from cache, or call lookup()
   return cert_cache_table:load(name)
end

local function certs_main()
   -- clear the fallback certificates and private keys
   -- set by the ssl_certificate and ssl_certificate_key
   -- directives above:
   local ok, err = ssl.clear_certs()
   if not ok then
      ngx.log(ngx.ERR, "failed to clear existing (fallback) certificates")
      return ngx.exit(ngx.ERROR)
   end

   -- Get TLS SNI (Server Name Indication) name set by the client
   local name, err = ssl.server_name()
   if not name then
      ngx.log(ngx.ERR, "failed to get SNI, err: ", err)
      return ngx.exit(ngx.ERROR)
   end

   local cert_data = load_cert_from_cache(name)
   if not cert_data then
      ngx.log(ngx.ERR, "Unable to load cert for: ", name)
      return ngx.exit(ngx.ERROR)
   end
   print("Cert Data: ", cert_data.cert)
end

certs_main()
