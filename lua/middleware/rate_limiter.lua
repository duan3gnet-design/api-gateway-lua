-- lua/middleware/rate_limiter.lua
-- Optimized: giảm key allocation, dùng incr atomic

local config   = require("config")
local response = require("utils.response")

local _M = {}
function _M.check()
    -- Cache config ở module level
    local MAX_REQUESTS   = config.rate_limit.max_requests
    local WINDOW_SECONDS = config.rate_limit.window_seconds
    local KEY_BY_USER    = (config.rate_limit.key_by == "user")
    local store          = ngx.shared.rate_limit_store

    -- Pre-build header values (constant strings)
    local MAX_REQUESTS_STR   = tostring(MAX_REQUESTS)
    local WINDOW_SECONDS_STR = tostring(WINDOW_SECONDS) .. "s"
    local RETRY_AFTER_STR    = tostring(WINDOW_SECONDS)

    -- ── Main ──────────────────────────────────────────────────────────────────
    local ctx = ngx.ctx
    local key
    if KEY_BY_USER and ctx.user_id and ctx.user_id ~= "" then
        key = "u:" .. ctx.user_id
    else
        key = "i:" .. ngx.var.binary_remote_addr  -- binary = 4 bytes, nhỏ hơn string IP
    end

    -- atomic incr – nếu key chưa tồn tại, init = 0 rồi incr lên 1
    local count, err = store:incr(key, 1, 0, WINDOW_SECONDS)
    if not count then
        -- Fail open: store lỗi thì cho qua
        ngx.log(ngx.ERR, "rate_limit store error: ", err)
        return
    end

    -- Set headers – chỉ set khi cần thiết
    ngx.header["X-RateLimit-Limit"]     = MAX_REQUESTS_STR
    ngx.header["X-RateLimit-Remaining"] = math.max(0, MAX_REQUESTS - count)
    ngx.header["X-RateLimit-Window"]    = WINDOW_SECONDS_STR

    if count > MAX_REQUESTS then
        ngx.header["Retry-After"] = RETRY_AFTER_STR
        response.too_many_requests()
    end

end
return _M