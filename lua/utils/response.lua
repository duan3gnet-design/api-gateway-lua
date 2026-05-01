-- lua/utils/response.lua
-- Helper gửi JSON response và kết thúc request

local _M = {}

function _M.error(status, code, message)
    ngx.status = status
    ngx.header["Content-Type"] = "application/json"
    ngx.header["X-Gateway"]    = "lua-gateway/1.0"
    ngx.say(string.format(
        '{"error":{"code":"%s","message":"%s"}}',
        code, message
    ))
    ngx.exit(status)
end

function _M.ok(data)
    ngx.status = 200
    ngx.header["Content-Type"] = "application/json"
    ngx.say(data)
end

-- Shortcut thường dùng
function _M.unauthorized(msg)
    _M.error(401, "UNAUTHORIZED", msg or "Token không hợp lệ hoặc đã hết hạn")
end

function _M.forbidden(msg)
    _M.error(403, "FORBIDDEN", msg or "Không có quyền truy cập tài nguyên này")
end

function _M.too_many_requests(msg)
    _M.error(429, "TOO_MANY_REQUESTS", msg or "Vượt quá giới hạn request")
end

return _M
