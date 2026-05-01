-- lua/admin/handler.lua
-- content_by_lua_file: admin API (chỉ localhost)

local cjson        = require("cjson")
local store_rl     = ngx.shared.rate_limit_store
local store_bl     = ngx.shared.jwt_blacklist
local logger       = require("utils.logger")
local openssl_hmac = require("resty.openssl.hmac")

ngx.header["Content-Type"] = "application/json"

local method = ngx.req.get_method()
local uri    = ngx.var.uri

-- ── GET /admin/stats ──────────────────────────────────────────────────────
if method == "GET" and uri == "/admin/stats" then
    local stats = {
        rate_limit_keys = store_rl:get_keys(0),
        blacklist_size  = #store_bl:get_keys(0),
        time            = ngx.now(),
    }
    ngx.say(cjson.encode(stats))
    return
end

-- ── POST /admin/debug-jwt  { "token": "...", "secret": "..." } ───────────
-- Dùng để debug chữ ký sai – CHỈ dùng lúc dev, tắt trên production
if method == "POST" and uri == "/admin/debug-jwt" then
    ngx.req.read_body()
    local body = ngx.req.get_body_data()
    local ok, data = pcall(cjson.decode, body or "")
    if not ok or not data or not data.token then
        ngx.status = 400
        ngx.say('{"error":"Cần trường token (và secret nếu muốn test)"}')
        return
    end

    local config = require("config")
    local secret = data.secret or config.jwt.secret

    -- Tách token
    local parts = {}
    for part in data.token:gmatch("[^%.]+") do
        parts[#parts + 1] = part
    end

    if #parts ~= 3 then
        ngx.say(cjson.encode({ error = "Token không đúng format header.payload.signature" }))
        return
    end

    local header_b64, payload_b64, sig_from_token = parts[1], parts[2], parts[3]

    -- Tính lại signature
    local signing_input = header_b64 .. "." .. payload_b64
    local h, err = openssl_hmac.new(secret, "sha256")
    h:update(signing_input)
    local digest = h:final()

    -- Encode theo nhiều cách để so sánh
    local b64_standard  = ngx.encode_base64(digest)
    local b64_url       = b64_standard:gsub("+", "-"):gsub("/", "_"):gsub("=", "")
    local b64_url_pad   = b64_standard:gsub("+", "-"):gsub("/", "_")  -- giữ padding =

    -- Decode header và payload để xem nội dung
    local function b64url_dec(s)
        s = s:gsub("-", "+"):gsub("_", "/")
        local pad = (4 - #s % 4) % 4
        s = s .. string.rep("=", pad)
        return ngx.decode_base64(s)
    end

    local header_json  = b64url_dec(header_b64)
    local payload_json = b64url_dec(payload_b64)

    local result = {
        -- Thông tin input
        signing_input      = signing_input,
        secret_length      = #secret,
        secret_preview     = secret:sub(1, 6) .. "...",

        -- Signature từ token gửi lên
        sig_from_token     = sig_from_token,

        -- Signature tính lại theo các kiểu encode
        sig_computed_b64url         = b64_url,        -- không có padding (chuẩn JWT)
        sig_computed_b64url_padded  = b64_url_pad,    -- có padding =
        sig_computed_b64_standard   = b64_standard,   -- standard base64

        -- Match check
        match_b64url        = (b64_url == sig_from_token),
        match_b64url_padded = (b64_url_pad == sig_from_token),
        match_b64_standard  = (b64_standard == sig_from_token),

        -- Nội dung decoded
        header  = header_json,
        payload = payload_json,
    }

    ngx.say(cjson.encode(result))
    return
end

-- ── POST /admin/blacklist ─────────────────────────────────────────────────
if method == "POST" and uri == "/admin/blacklist" then
    ngx.req.read_body()
    local body = ngx.req.get_body_data()
    local ok, data = pcall(cjson.decode, body or "")
    if not ok or not data or not data.jti then
        ngx.status = 400
        ngx.say('{"error":"Cần trường jti"}')
        return
    end
    local ttl = tonumber(data.ttl) or 3600
    store_bl:set("jti:" .. data.jti, true, ttl)
    logger.info("[ADMIN] Blacklisted jti=" .. data.jti .. " ttl=" .. ttl)
    ngx.say(cjson.encode({ ok = true, jti = data.jti, ttl = ttl }))
    return
end

-- ── DELETE /admin/rate-limit?key=rl:ip:x.x.x.x ──────────────────────────
if method == "DELETE" and uri == "/admin/rate-limit" then
    local key = ngx.var.arg_key
    if not key then
        ngx.status = 400
        ngx.say('{"error":"Cần query param key"}')
        return
    end
    store_rl:delete(key)
    ngx.say(cjson.encode({ ok = true, deleted = key }))
    return
end

-- 404
ngx.status = 404
ngx.say('{"error":"Admin endpoint không tồn tại"}')
