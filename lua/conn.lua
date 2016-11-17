-- Copyright (C) 2015 Suhaimi Amir <suhaimi@tbd.my> ---

local mysql = require "resty.mysql"
-- local cjson = require "cjson"

local db, err = mysql:new()
if not db then
   ngx.log(ngx.ERR,"failed to instantiate mysql: ", err)
  return
end

db:set_timeout(2000) -- 1 sec

local ok, err, errno, sqlstate = db:connect {
  host = "127.0.0.1",
  port = 3306,
  database = "shout",
  user = "shout",
  password = "sh0ut",
  max_packet_size = 1024 * 1024
}

if not ok then
   ngx.log(ngx.ERR, "failed to connect: ", err, ": ", errno, " ", sqlstate)
   ngx.exit(444);
  return
end

local channel = ngx.quote_sql_str(ngx.var[2])
local q = "select * from ts_channel where channel = " .. channel
res, err, errno, sqlstate = db:query(q, 1)

if res then
  local secret_key = res[1].secret_key
  local post_url = res[1].post_url

  if secret_key then
    ngx.var.channel_secret = secret_key
    ngx.var.post_url = post_url

    local server_hash_old = ngx.md5(ngx.var[2] .. secret_key)
    if ngx.var[3] then
      local server_hash = ngx.md5(ngx.var[2] .. secret_key .. ngx.var[3]) -- channel + secret key + name
    end

    if server_hash_old == ngx.var[1] then
      --old
    elseif server_hash == ngx.var[1] then
      --new
    else
      ngx.exit(403)
    end
  else
    ngx.exit(444);
  end
end
