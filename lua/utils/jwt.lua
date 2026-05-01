-- lua/utils/jwt.lua
local _M = {}

local openssl_hmac = require("resty.openssl.hmac")
local cjson        = require("cjson")
local _json_decode = cjson.decode

-- ── Helpers ───────────────────────────────────────────────────────────────

local function base64url_decode(s)
    s = s:gsub("-", "+"):gsub("_", "/")
    local pad = (4 - #s % 4) % 4
    if pad < 4 then s = s .. string.rep("=", pad) end
    return ngx.decode_base64(s)
end

local function base64url_encode(s)
    local b64 = ngx.encode_base64(s)
    b64 = b64:gsub("+", "-")
    b64 = b64:gsub("/", "_")
    b64 = b64:gsub("=+$", "")
    return b64
end

---JJWT dùng Decoders.BASE64.decode(secret) → secret trong config là Base64,
---cần decode ra raw bytes trước khi dùng làm HMAC key
local function decode_secret(secret)
    -- Standard Base64 decode (JJWT Decoders.BASE64)
    local decoded = ngx.decode_base64(secret)
    if decoded then
        ngx.log(ngx.DEBUG, "[JWT] secret decoded from Base64, raw length=", #decoded)
        return decoded
    end
    -- Fallback: plain text secret (không phải Base64)
    ngx.log(ngx.DEBUG, "[JWT] secret used as plain text, length=", #secret)
    return secret
end

-- Cache decoded secret per worker (decode 1 lần duy nhất)
local _secret_cache = {}

local function get_raw_secret(secret)
    if not _secret_cache[secret] then
        _secret_cache[secret] = decode_secret(secret)
    end
    return _secret_cache[secret]
end

-- ── Public API ────────────────────────────────────────────────────────────

function _M.verify(token, secret)
    if not token then return nil, "token is nil" end

    -- Tách header.payload.signature
    local dot1 = token:find(".", 1, true)
    if not dot1 then return nil, "JWT format không hợp lệ" end
    local dot2 = token:find(".", dot1 + 1, true)
    if not dot2 then return nil, "JWT format không hợp lệ" end

    local header_b64  = token:sub(1, dot1 - 1)
    local payload_b64 = token:sub(dot1 + 1, dot2 - 1)
    local sig_b64     = token:sub(dot2 + 1)

    -- Dùng raw bytes của secret (đã decode Base64)
    local raw_secret = get_raw_secret(secret)

    -- Tính HMAC-SHA256
    local signing_input = header_b64 .. "." .. payload_b64
    local h, err = openssl_hmac.new(raw_secret, "sha256")
    if not h then return nil, "HMAC init lỗi: " .. (err or "") end

    h:update(signing_input)
    local digest
    digest, err = h:final()
    if not digest then return nil, "HMAC final lỗi: " .. (err or "") end

    -- So sánh signature
    local computed = base64url_encode(digest)
    if computed ~= sig_b64 then
        return nil, "Chữ ký JWT không hợp lệ"
    end

    -- Decode payload
    local payload_json = base64url_decode(payload_b64)
    if not payload_json then return nil, "base64url decode payload thất bại" end

    local ok, payload = pcall(_json_decode, payload_json)
    if not ok then return nil, "JSON decode payload thất bại" end

    -- Kiểm tra thời hạn
    local now = ngx.time()
    if payload.exp and payload.exp < now then
        return nil, string.format("Token hết hạn (exp=%d)", payload.exp)
    end
    if payload.nbf and payload.nbf > now then
        return nil, "Token chưa có hiệu lực"
    end

    return payload, nil
end

function _M.extract_token()
    local auth = ngx.req.get_headers()["Authorization"]
    if not auth then return nil end
    return auth:match("^[Bb]earer%s+(.+)$")
end

return _M
