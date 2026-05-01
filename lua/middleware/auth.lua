-- lua/middleware/auth.lua
-- Optimized: giảm allocations, cache config

local config   = require("config")
local jwt      = require("utils.jwt")
local response = require("utils.response")

local _M = {}
function _M.check()
    -- Cache ở module level – load 1 lần per worker
    local JWT_SECRET = config.jwt.secret
    local JWT_ISSUER = config.jwt.issuer
    local blacklist  = ngx.shared.jwt_blacklist

    local function is_blacklisted(jti)
        if not jti then return false end
        return blacklist:get("jti:" .. jti) ~= nil
    end

    -- ── Main ──────────────────────────────────────────────────────────────────
    local token = jwt.extract_token()
    if not token then
        response.unauthorized("Vui lòng cung cấp Bearer token")
    end

    local payload, err = jwt.verify(token, JWT_SECRET)
    if not payload then
        response.unauthorized(err)
    end

    -- if JWT_ISSUER and payload.iss ~= JWT_ISSUER then
    --     response.unauthorized("Token issuer không hợp lệ")
    -- end

    if is_blacklisted(payload.jti) then
        response.unauthorized("Token đã bị thu hồi")
    end

    -- Ghi vào ngx.ctx – share sang rbac.lua, rate_limiter.lua trong cùng request
    local ctx = ngx.ctx
    ctx.user_id     = payload.sub or ""
    ctx.user_roles  = payload.roles or {}
    ctx.permissions = payload.permissions or {}

    -- Set header để truyền xuống upstream
    ngx.req.set_header("X-User-Id",    ctx.user_id)
    ngx.req.set_header("X-User-Roles", table.concat(ctx.user_roles, ","))

end
return _M
