-- lua/middleware/rate_limit_fn.lua
-- Function-style rate limiter

local _M  = {}
local store = ngx.shared.rate_limit_store

function _M.check(max_requests, window_seconds)
    local ctx = ngx.ctx
    local key
    if ctx.user_id and ctx.user_id ~= "" then
        key = "u:" .. ctx.user_id
    else
        key = "i:" .. ngx.var.binary_remote_addr
    end

    local count, err = store:incr(key, 1, 0, window_seconds)
    if not count then
        ngx.log(ngx.ERR, "rate_limit store error: ", err)
        return true, nil  -- fail open
    end

    ngx.header["X-RateLimit-Limit"]     = max_requests
    ngx.header["X-RateLimit-Remaining"] = math.max(0, max_requests - count)
    ngx.header["X-RateLimit-Window"]    = window_seconds .. "s"

    if count > max_requests then
        ngx.header["Retry-After"] = window_seconds
        return false, string.format(
            "Vượt quá %d request / %ds", max_requests, window_seconds)
    end
    return true, nil
end

return _M
