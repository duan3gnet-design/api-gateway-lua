-- lua/middleware/auth_fn.lua
-- Function-style auth (trả về ok/err thay vì ngx.exit)
-- Dùng bởi router.lua

local jwt    = require("utils.jwt")
local config = require("config")

local _M         = {}
local JWT_SECRET = config.jwt.secret
local JWT_ISSUER = config.jwt.issuer
local blacklist  = ngx.shared.jwt_blacklist

function _M.verify()
    local token = jwt.extract_token()
    if not token then
        return false, "Vui lòng cung cấp Bearer token"
    end

    local payload, err = jwt.verify(token, JWT_SECRET)
    if not payload then
        return false, err
    end

    if JWT_ISSUER and payload.iss ~= JWT_ISSUER then
        return false, "Token issuer không hợp lệ"
    end

    if payload.jti and blacklist:get("jti:" .. payload.jti) then
        return false, "Token đã bị thu hồi"
    end

    -- Lưu vào ngx.ctx để dùng ở bước sau
    local ctx       = ngx.ctx
    ctx.user_id     = payload.sub or ""
    ctx.user_roles  = payload.roles or {}
    ctx.permissions = payload.permissions or {}

    ngx.req.set_header("X-User-Id",    ctx.user_id)
    ngx.req.set_header("X-User-Roles", table.concat(ctx.user_roles, ","))

    return true, nil
end

return _M
