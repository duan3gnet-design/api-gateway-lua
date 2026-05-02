-- lua/config.lua
local _M = {}

-- ── JWT ───────────────────────────────────────────────────────────────────
_M.jwt = {
    secret    = os.getenv("JWT_SECRET") or "change-me-super-secret-key-32chars!!",
    issuer    = os.getenv("JWT_ISSUER") or "auth-service",
    algorithm = "HS256",
}

-- ── Database (PostgreSQL) ─────────────────────────────────────────────────
_M.db = {
    host     = os.getenv("DB_HOST")     or "host.docker.internal",
    port     = os.getenv("DB_PORT")     or "5432",
    name     = os.getenv("DB_NAME")     or "gateway_db",
    user     = os.getenv("DB_USER")     or "postgres",
    password = os.getenv("DB_PASSWORD") or "postgres",
}

-- ── Route reload ──────────────────────────────────────────────────────────
_M.route_reload = {
    -- Polling interval (giây). Set 0 để tắt polling.
    interval = tonumber(os.getenv("ROUTE_RELOAD_INTERVAL")) or 30,
}

-- ── Rate Limiting (default, override per-route từ DB) ─────────────────────
_M.rate_limit = {
    max_requests   = tonumber(os.getenv("RATE_LIMIT_MAX"))    or 100,
    window_seconds = tonumber(os.getenv("RATE_LIMIT_WINDOW")) or 60,
}

-- ── RBAC permission map (vẫn giữ trong code, ít thay đổi) ────────────────
_M.rbac = {
    ["GET"] = {
        ["/api/resource/items"]      = "items:READ",
        ["/api/resource/items/(.+)"] = "items:READ",
    },
    ["POST"] = {
        ["/api/resource/items"]      = "items:CREATE",
    },
    ["PUT"] = {
        ["/api/resource/items/(.+)"] = "items:UPDATE",
    },
    ["DELETE"] = {
        ["/api/resource/items/(.+)"] = "items:DELETE",
    },
}

return _M
