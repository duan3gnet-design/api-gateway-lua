-- lua/store/route_store.lua
-- Load routes + upstreams từ PostgreSQL, cache vào lua_shared_dict
-- Reload thủ công qua Admin API POST /admin/routes/reload

local _M = {}

local pgmoon = require("pgmoon")
local cjson  = require("cjson")
local config = require("config")

local shared        = ngx.shared.route_store
local ROUTES_KEY    = "routes_v1"
local UPSTREAMS_KEY = "upstreams_v1"
local LOADED_AT_KEY = "loaded_at"

-- ── DB connection ─────────────────────────────────────────────────────────

local function new_pg()
    local pg = pgmoon.new({
        host     = config.db.host,
        port     = config.db.port,
        database = config.db.name,
        user     = config.db.user,
        password = config.db.password,
    })
    local ok, err = pg:connect()

    if not ok then
        return nil, "Không kết nối được PostgreSQL: " .. (err or "")
    end

    return pg, nil
end

-- ── Helpers ───────────────────────────────────────────────────────────────

local function pg_bool(v)
    return v == true or v == "t" or v == "true"
end

local function decode_json_col(v)
    if not v then return nil end
    if type(v) == "table" then return v end
    local ok, decoded = pcall(cjson.decode, v)
    return ok and decoded or nil
end

-- ── Load từ DB ────────────────────────────────────────────────────────────

local function load_from_db()
    local pg, err = new_pg()
    if not pg then return nil, nil, err end

    -- Upstreams
    local upstreams_raw, qerr = pg:query([[
        SELECT name, targets
        FROM   gateway_upstreams
        WHERE  enabled = TRUE
    ]])
    if not upstreams_raw then
        return nil, nil, "Query upstreams lỗi: " .. (qerr or "")
    end

    -- Routes – sort theo prefix dài nhất (longest-prefix match)
    local routes_raw
    routes_raw, qerr = pg:query([[
        SELECT r.path_prefix,
               r.upstream_name,
               r.auth_required,
               r.rbac_permissions,
               r.rate_limit_max,
               r.rate_limit_window,
               r.strip_prefix
        FROM   gateway_routes r
        JOIN   gateway_upstreams u ON u.name = r.upstream_name
        WHERE  r.enabled = TRUE
          AND  u.enabled = TRUE
        ORDER  BY length(r.path_prefix) DESC
    ]])
    if not routes_raw then
        return nil, nil, "Query routes lỗi: " .. (qerr or "")
    end

    pg:keepalive(10000, 5)

    -- Build upstreams: name → targets[]
    local upstreams = {}
    for _, row in ipairs(upstreams_raw) do
        upstreams[row.name] = decode_json_col(row.targets) or {}
    end

    -- Build routes[]
    local routes = {}
    for _, row in ipairs(routes_raw) do
        routes[#routes + 1] = {
            path_prefix       = row.path_prefix,
            upstream_name     = row.upstream_name,
            auth_required     = pg_bool(row.auth_required),
            rbac_permissions  = decode_json_col(row.rbac_permissions), -- {GET="orders:READ",...} | nil
            rate_limit_max    = tonumber(row.rate_limit_max),
            rate_limit_window = tonumber(row.rate_limit_window),
            strip_prefix      = pg_bool(row.strip_prefix),
        }
    end

    return routes, upstreams, nil
end

-- ── Shared dict cache ─────────────────────────────────────────────────────

local function save_to_cache(routes, upstreams)
    shared:set(ROUTES_KEY,    cjson.encode(routes))
    shared:set(UPSTREAMS_KEY, cjson.encode(upstreams))
    shared:set(LOADED_AT_KEY, ngx.time())
end

local function load_from_cache()
    local rj = shared:get(ROUTES_KEY)
    local uj = shared:get(UPSTREAMS_KEY)
    if not rj or not uj then return nil, nil end
    local ok1, routes    = pcall(cjson.decode, rj)
    local ok2, upstreams = pcall(cjson.decode, uj)
    if not ok1 or not ok2 then return nil, nil end
    return routes, upstreams
end

-- ── Public API ────────────────────────────────────────────────────────────

-- Reload từ DB và cập nhật shared dict cache
-- Được gọi từ init_worker và Admin API
function _M.reload()
    local routes, upstreams, err = load_from_db()
    if err then
        ngx.log(ngx.ERR, "[route_store] reload lỗi: ", err)
        return false, err
    end
    save_to_cache(routes, upstreams)
    local n_up = 0
    for _ in pairs(upstreams) do n_up = n_up + 1 end
    ngx.log(ngx.INFO, string.format(
        "[route_store] Loaded %d routes, %d upstreams", #routes, n_up
    ))
    return true, nil
end

-- Lấy routes từ cache (không query DB)
function _M.get_routes()
    local routes, upstreams = load_from_cache()
    if not routes then
        -- Cache miss: xảy ra khi worker khác chưa kịp load
        local ok, err = _M.reload()
        if not ok then return {}, {}, err end
        routes, upstreams = load_from_cache()
    end
    return routes or {}, upstreams or {}
end

-- Longest-prefix match
function _M.match(uri)
    local routes, upstreams = _M.get_routes()
    for _, route in ipairs(routes) do
        if uri:sub(1, #route.path_prefix) == route.path_prefix then
            -- Clone để tránh mutate cache
            local matched = {}
            for k, v in pairs(route) do matched[k] = v end
            matched.targets = upstreams[route.upstream_name] or {}
            return matched
        end
    end
    return nil
end

-- Thông tin cache (dùng cho admin stats)
function _M.info()
    local loaded_at = shared:get(LOADED_AT_KEY) or 0
    local routes    = load_from_cache()
    return {
        loaded_at   = loaded_at,
        route_count = routes and #routes or 0,
        age_seconds = ngx.time() - loaded_at,
    }
end

return _M
