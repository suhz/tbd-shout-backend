local server = require "resty.websocket.server"
local redis = require "resty.redis"
local mysql = require "resty.mysql"
local cjson = require "cjson"
local http = require "resty.http"

--local cmsgpack = require "MessagePack"
--lua_package_path "/usr/local/lib/lua/resty/?.lua;;";
--local httpc = http.new()
--local str = require "resty.string"

local redis_host = "tbd-chat.zwesvz.0001.apse1.cache.amazonaws.com"
local redis_port = 6379

function sanitize(txt)
  local replacements = {
    ['&' ] = '&amp;',
    ['<' ] = '&lt;',
    ['>' ] = '&gt;'
  }
  return txt
  :gsub('[&<>\n]', replacements)
  :gsub(' +', function(s) return ' '..('&nbsp;'):rep(#s-1) end)
end

-- redis: lpush -> rpop

-- websocket --
local wb, err = server:new{
  timeout = 5000,
  max_payload_len = 65535
}

if not wb then
  ngx.log(ngx.ERR, "failed to new websocket: ", err)
  return ngx.exit(444)
end

-- redis subs --
local function subs(ws)
  local sub = redis:new()
  -- sub:connect("127.0.0.1", 6379)
  sub:connect(redis_host, redis_port)
  sub:subscribe("c." .. ngx.var[2])
  sub:set_timeout(1000) -- 1 sec
  while true do
    local bytes, err = sub:read_reply()
    if bytes then
      wb:send_text(bytes[3])
    end
    if err then
      if err ~= "timeout" then
        ngx.log(ngx.ERR, "redis read error: ", err)
        return ngx.exit(444)
      end
    end
  end
end

ngx.thread.spawn(subs, ws)

local pub = redis:new()
--pub:connect("127.0.0.1", 6379)
pub:connect(redis_host, redis_port)
--pub:set_timeout(21600)

while true do
  local data, typ, err = wb:recv_frame()

  if wb.fatal then
    ngx.log(ngx.ERR, "failed to receive frame: ", err)
    return ngx.exit(444)
  end

  if not data then
    local bytes, err = wb:send_ping()

    if not bytes then
      ngx.log(ngx.ERR, "failed to send ping: ", err)
      return ngx.exit(444)
    end

    elseif typ == "close" then break
    elseif typ == "ping" then
      local bytes, err = wb:send_pong()
      if not bytes then
        ngx.log(ngx.ERR, "failed to send pong: ", err)
        return ngx.exit(444)
      end
    elseif typ == "pong" then
      --ngx.log(ngx.INFO, "client ponged")

    elseif typ == "text" then
      --local bytes, err = wb:send_text("testingx " .. data)
      --if not bytes then
      --ngx.log(ngx.ERR, "failed to send text: ", err)
      --return ngx.exit(444)
      --end

      local channel = "c." .. ngx.var[2]

      if data then

        local decoded = cjson.decode(data)

        if decoded.msg ~= "" then
          decoded.channel = ngx.var[2]
          decoded.msg_ip = ngx.var.remote_addr
          decoded.masa = ngx.now()

          local packed = cjson.encode(decoded)

          local httpc = http.new()
          local res, err = httpc:request_uri(ngx.var.post_url .. "&key=" .. ngx.var.channel_secret, {
            method = "POST",
            body = ngx.encode_args({push=packed}),
            headers = {
              ["Content-Type"] = "application/x-www-form-urlencoded",
            }
          })

          if not res then
            ngx.log(ngx.ERR, "failed to request: ", packed, err)
            return
          end

          if res.body ~= "" then
            res, err = pub:publish(channel, res.body)
            if not res then
              ngx.log(ngx.ERR, "failed to publish: ", err)
              return
            end
          end

        end -- text
      end
    end
  end
wb:send_close()
pub:close()
sub:close()
