-- lua/admin/handler.lua
local cjson       = require("cjson")
local store_rl    = ngx.shared.rate_limit_store
local store_bl    = ngx.shared.jwt_blacklist
local route_store = require("store.route_store")

ngx.header["Content-Type"] = "application/json"

local method = ngx.req.get_method()
local uri    = ngx.var.uri

local function read_body_json()
    ngx.req.read_body()
    local body = ngx.req.get_body_data()
    if not body then return nil end
    local ok, data = pcall(cjson.decode, body)
    return ok and data or nil
end

-- ── POST /admin/routes/reload ─────────────────────────────────────────────
-- Manual trigger reload routes từ DB
if method == "POST" and uri == "/admin/routes/reload" then
    local ok, err = route_store.reload()
    if not ok then
        ngx.status = 500
        ngx.say(cjson.encode({ ok = false, error = err }))
        return
    end
    ngx.say(cjson.encode({
        ok   = true,
        info = route_store.info(),
    }))
    return
end

-- ── GET /admin/routes ─────────────────────────────────────────────────────
-- Xem danh sách routes đang có trong cache
if method == "GET" and uri == "/admin/routes" then
    local routes, upstreams = route_store.get_routes()
    ngx.say(cjson.encode({
        info      = route_store.info(),
        routes    = routes,
        upstreams = upstreams,
    }))
    return
end

-- ── GET /admin/stats ──────────────────────────────────────────────────────
if method == "GET" and uri == "/admin/stats" then
    ngx.say(cjson.encode({
        routes          = route_store.info(),
        rate_limit_keys = store_rl:get_keys(100),
        blacklist_size  = #store_bl:get_keys(0),
        time            = ngx.now(),
    }))
    return
end

-- ── POST /admin/blacklist  { "jti":"...", "ttl":3600 } ───────────────────
if method == "POST" and uri == "/admin/blacklist" then
    local data = read_body_json()
    if not data or not data.jti then
        ngx.status = 400
        ngx.say('{"error":"Cần trường jti"}')
        return
    end
    local ttl = tonumber(data.ttl) or 3600
    store_bl:set("jti:" .. data.jti, true, ttl)
    ngx.say(cjson.encode({ ok = true, jti = data.jti, ttl = ttl }))
    return
end

-- ── POST /admin/debug-jwt  { "token":"..." } ─────────────────────────────
if method == "POST" and uri == "/admin/debug-jwt" then
    local data = read_body_json()
    if not data or not data.token then
        ngx.status = 400
        ngx.say('{"error":"Cần trường token"}')
        return
    end
    local config      = require("config")
    local openssl_hmac = require("resty.openssl.hmac")
    local secret      = data.secret or config.jwt.secret

    local parts = {}
    for p in data.token:gmatch("[^%.]+") do parts[#parts+1] = p end
    if #parts ~= 3 then
        ngx.say('{"error":"Token không đúng format"}'); return
    end

    local header_b64, payload_b64, sig_from_token = parts[1], parts[2], parts[3]
    local signing_input = header_b64 .. "." .. payload_b64

    -- Decode secret (JJWT BASE64 style)
    local raw_secret = ngx.decode_base64(secret) or secret

    local h = openssl_hmac.new(raw_secret, "sha256")
    h:update(signing_input)
    local digest  = h:final()
    local b64     = ngx.encode_base64(digest)
    local b64url  = b64:gsub("+","-"):gsub("/","_"):gsub("=+$","")

    local function b64url_dec(s)
        s = s:gsub("-","+"):gsub("_","/")
        local pad = (4 - #s % 4) % 4
        if pad < 4 then s = s .. string.rep("=", pad) end
        return ngx.decode_base64(s)
    end

    ngx.say(cjson.encode({
        secret_length      = #secret,
        raw_secret_length  = #raw_secret,
        secret_preview     = secret:sub(1,6) .. "...",
        sig_from_token     = sig_from_token,
        sig_computed       = b64url,
        match              = (b64url == sig_from_token),
        header             = b64url_dec(header_b64),
        payload            = b64url_dec(payload_b64),
    }))
    return
end

-- ── DELETE /admin/rate-limit?key=... ─────────────────────────────────────
if method == "DELETE" and uri == "/admin/rate-limit" then
    local key = ngx.var.arg_key
    if not key then
        ngx.status = 400; ngx.say('{"error":"Cần query param ?key="}'); return
    end
    store_rl:delete(key)
    ngx.say(cjson.encode({ ok = true, deleted = key }))
    return
end

ngx.status = 404
ngx.say('{"error":"Admin endpoint không tồn tại","uri":"' .. uri .. '"}')
