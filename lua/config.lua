-- lua/config.lua
-- Toàn bộ cấu hình gateway tập trung tại đây

local _M = {}

-- ── JWT ───────────────────────────────────────────────────────────────────
_M.jwt = {
    secret          = os.getenv("JWT_SECRET") or "change-me-super-secret-key-32chars!!",
    issuer          = os.getenv("JWT_ISSUER") or "auth-service",
    algorithm       = "HS256",
    -- Header name chứa token (Authorization: Bearer <token>)
    header          = "Authorization",
}

-- ── Rate Limiting ─────────────────────────────────────────────────────────
_M.rate_limit = {
    -- Số request tối đa trong window
    max_requests    = tonumber(os.getenv("RATE_LIMIT_MAX")) or 100,
    -- Cửa sổ thời gian (giây)
    window_seconds  = tonumber(os.getenv("RATE_LIMIT_WINDOW")) or 60,
    -- Key: "ip" hoặc "user" (dùng user_id nếu đã auth)
    key_by          = "ip",
}

-- ── Upstream Services ─────────────────────────────────────────────────────
_M.services = {
    auth = {
        name    = "auth_service",
        prefix  = "/api/auth",
        -- Các path không cần JWT
        public_paths = {
            "/api/auth/login",
            "/api/auth/register",
            "/api/auth/refresh",
            "/api/auth/validate",
            "/api/auth/oauth2/",
        },
    },
    resource = {
        name   = "resource_service",
        prefix = "/api/resources",
    },
    whoami = {
        name   = "who_am_i",
        prefix = "/who-am-i",
    },
}

-- ── RBAC: permission map ──────────────────────────────────────────────────
-- Format: [method][path_pattern] = required_permission
-- Permission khớp với format "resource:action" trong JWT claim "permissions"
_M.rbac = {
    ["GET"]    = {
        ["/api/resources/items"]     = "items:read",
        ["/api/resources/items/(.+)"] = "items:read",
        ["/api/resources/admin"]     = "admin:read",
    },
    ["POST"]   = {
        ["/api/resources/items"]     = "items:write",
    },
    ["PUT"]    = {
        ["/api/resources/items/(.+)"] = "items:write",
    },
    ["DELETE"] = {
        ["/api/resources/items/(.+)"] = "items:delete",
        ["/api/resources/admin/(.+)"] = "admin:delete",
    },
}

-- ── Logging ───────────────────────────────────────────────────────────────
_M.log = {
    level = os.getenv("LOG_LEVEL") or "info",  -- debug | info | warn | error
}

return _M
