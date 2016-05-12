-- Copyright (C) 2016 Matthieu Tourne

-- Used to manipulate certs in the ssl_certificate_by_lua*
-- directive.
-- part of lua-resty-core, ships with OpenResty
local ssl = require("ngx.ssl")

-- Keep cache in a shared memory segment
-- (git submodule in lua/libs)
-- Note: if you need a lot of performance, it might makes
--   sense to also cache the data per-worker, on top
--   of in shared memory :
--   https://github.com/openresty/lua-resty-lrucache

local shcache = require("libs/shcache/shcache")

-- Used as a serializer for shcache.
-- part of OpenResty, could be swapped with cmsgpack
local cjson = require("cjson")


local CERT_DIRECTORY = 'conf/certs/'

local function load_cert_from_cache(name)
   local lookup = function ()
      -- load from disk as a demo. You should probably load it
      -- from a local redis / memcache

      -- load cert
      local f, err = io.open(CERT_DIRECTORY .. name .. '.pem')
      if not f then
         return nil, err
      end

      -- "*a": reads the whole file
      local cert = f:read("*a")

      f:close()

      -- load key
      local f, err = io.open(CERT_DIRECTORY .. name .. '.key')
      if not f then
         return nil, err
      end

      local key = f:read("*a")

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

local function load_cert_matching(name)
   -- try for exact host match first
   -- then for '*.'

   local cert_data = load_cert_from_cache(name)
   if cert_data then
      return cert_data
   end

   -- finds the first dot in the name
   -- contatenates a star to that.
   -- example.foo.com becomes *.foo.com
   local dot_pos = string.find(name, "%.") -- %. escapes '.' the matching character
   star_name = "*" .. string.sub(name, dot_pos)

   return load_cert_from_cache(star_name)
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

   print("SNI: ", name)

   local cert_data = load_cert_matching(name)
   if not cert_data then
      ngx.log(ngx.ERR, "Unable to load suitable cert for: ", name)
      return ngx.exit(ngx.ERROR)
   end

   local der_cert_chain, err = ssl.cert_pem_to_der(cert_data.cert)
   if not der_cert_chain then
      ngx.log(ngx.ERR, "Unable to load PEM for: ", name,
              ", err: ", err)
      return ngx.exit(ngx.ERROR)
   end

   local ok, err = ssl.set_der_cert(der_cert_chain)
   if not ok then
      ngx.log(ngx.ERR, "Unable te set cert for: ", name,
              ", err: ", err)
      return ngx.exit(ngx.ERROR)
   end

   local der_priv_key, err = ssl.priv_key_pem_to_der(cert_data.key)
   if not der_priv_key then
      ngx.log(ngx.ERR, "Unable to load PEM KEY for: ", name,
              ", err: ", err)
      return ngx.exit(ngx.ERROR)
   end

   local ok, err = ssl.set_der_priv_key(der_priv_key)
   if not ok then
      ngx.log(ngx.ERR, "Unable te set cert key for: ", name,
              ", err: ", err)
      return ngx.exit(ngx.ERROR)
   end
end

certs_main()
