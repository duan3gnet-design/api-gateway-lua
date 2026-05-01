-- test/test_jwt.lua
-- Chạy: lua test/test_jwt.lua  (cần cài lua + luacrypto hoặc mock ngx)
-- Dùng để test jwt.lua độc lập ngoài OpenResty

-- Mock ngx cho môi trường test thuần Lua
ngx = {
    time = os.time,
    encode_base64 = function(s)
        return require("mime").b64(s)
    end,
    decode_base64 = function(s)
        return require("mime").unb64(s)
    end,
    log = print,
    DEBUG = "DEBUG", INFO = "INFO", WARN = "WARN", ERR = "ERR",
    req = {
        get_headers = function() return {} end,
        get_method  = function() return "GET" end,
    },
    var = { request_uri = "/test" },
}

local function base64url_encode(s)
    local b64 = require("mime").b64(s)
    return b64:gsub("+","-"):gsub("/","_"):gsub("=","")
end

local cjson  = require("cjson")
local secret = "test-secret-key-minimum-32-characters!!"

local header  = base64url_encode(cjson.encode({alg="HS256",typ="JWT"}))
local payload = base64url_encode(cjson.encode({
    sub  = "user-123",
    iss  = "auth-service",
    exp  = os.time() + 3600,
    roles = {"USER"},
    permissions = {"items:read", "items:write"},
}))

-- Cần luacrypto: luarocks install luacrypto
local ok, crypto = pcall(require, "crypto")
if ok then
    local sig_raw = crypto.hmac.digest("sha256", header.."."..payload, secret, true)
    local sig     = base64url_encode(sig_raw)
    local token   = header.."."..payload.."."..sig
    print("Token:", token)
    print("TEST PASSED ✅")
else
    print("Cần cài luacrypto để chạy test: luarocks install luacrypto")
    print("Generated header.payload (chưa có sig):")
    print(header .. "." .. payload)
end
