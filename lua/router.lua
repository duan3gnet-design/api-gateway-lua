-- lua/router.lua
-- Dynamic reverse proxy: match route từ DB, auth + rbac + rate limit per route

local route_store  = require("store.route_store")
local auth         = require("middleware.auth")
local rate_limit   = require("middleware.rate_limiter")
local response     = require("utils.response")

local uri    = ngx.var.uri
local method = ngx.req.get_method()

-- ── 1. Match route ────────────────────────────────────────────────────────
local route = route_store.match(uri)
if not route then
    return response.error(404, "NOT_FOUND", "Route không tồn tại: " .. uri)
end

-- ── 2. Auth ───────────────────────────────────────────────────────────────
if route.auth_required then
    local ok, err = auth.verify()
    if not ok then return response.unauthorized(err) end
end

-- ── 3. RBAC per route (từ DB) ─────────────────────────────────────────────
if route.auth_required and route.rbac_permissions then
    local required = route.rbac_permissions[method]
    if required then
        -- Build permission set từ JWT payload (đã set trong auth)
        local ctx = ngx.ctx
        if not ctx.perm_set then
            local set = {}
            for _, p in ipairs(ctx.permissions or {}) do set[p] = true end
            ctx.perm_set = set
        end

        local granted = ctx.perm_set[required]
                     or ctx.perm_set["*:*"]

        -- Wildcard resource: "orders:*" covers "orders:READ"
        if not granted then
            local resource = required:match("^([^:]+):")
            if resource then
                granted = ctx.perm_set[resource .. ":*"]
            end
        end

        if not granted then
            return response.forbidden(string.format(
                "Cần quyền '%s' để %s %s", required, method, uri
            ))
        end
    end
end

-- ── 4. Rate limit per route ───────────────────────────────────────────────
local rl_ok, rl_err = rate_limit.check(route.rate_limit_max, route.rate_limit_window)
if not rl_ok then return response.too_many_requests(rl_err) end

-- ── 5. Chọn upstream target (weighted round-robin) ────────────────────────
local targets = route.targets
if not targets or #targets == 0 then
    return response.error(502, "NO_UPSTREAM",
        "Không có upstream cho route: " .. route.upstream_name)
end

local rr_key     = "rr:" .. route.upstream_name
local idx        = ngx.shared.rr_store:incr(rr_key, 1, 0)
local target     = targets[((idx - 1) % #targets) + 1]
local upstream_url = "http://" .. target.host .. ":" .. tostring(target.port)

-- ── 6. Build proxy path ───────────────────────────────────────────────────
local proxy_path = uri
if route.strip_prefix then
    proxy_path = uri:sub(#route.path_prefix + 1)
    if proxy_path == "" or proxy_path:sub(1, 1) ~= "/" then
        proxy_path = "/" .. proxy_path
    end
end
local args = ngx.var.args
if args and args ~= "" then
    proxy_path = proxy_path .. "?" .. args
end

-- ── 7. Proxy request ──────────────────────────────────────────────────────
local httpc = require("resty.http").new()
httpc:set_timeout(30000)

-- Forward headers
local req_headers = ngx.req.get_headers()
req_headers["Host"]              = target.host .. ":" .. tostring(target.port)
req_headers["X-Real-IP"]         = ngx.var.remote_addr
req_headers["X-Forwarded-For"]   = ngx.var.proxy_add_x_forwarded_for
req_headers["X-Forwarded-Proto"] = ngx.var.scheme

local ctx = ngx.ctx
if ctx.user_id then
    req_headers["X-User-Id"]    = ctx.user_id
    req_headers["X-User-Roles"] = table.concat(ctx.user_roles or {}, ",")
end

ngx.req.read_body()

local res, err = httpc:request_uri(upstream_url .. proxy_path, {
    method            = method,
    body              = ngx.req.get_body_data(),
    headers           = req_headers,
    keepalive_timeout = 60000,
    keepalive_pool    = 64,
})

if not res then
    ngx.log(ngx.ERR, "[router] upstream lỗi: ", err,
            " | upstream=", route.upstream_name,
            " | target=", target.host, ":", target.port)
    return response.error(502, "BAD_GATEWAY",
        "Upstream '" .. route.upstream_name .. "' không phản hồi")
end

-- ── 8. Trả response ───────────────────────────────────────────────────────
ngx.status = res.status

local skip = { ["transfer-encoding"]=true, ["connection"]=true, ["keep-alive"]=true }
for k, v in pairs(res.headers) do
    if not skip[k:lower()] then ngx.header[k] = v end
end

ngx.header["X-Gateway"]              = "lua-gateway/1.0"
ngx.header["X-Content-Type-Options"] = "nosniff"
ngx.header["Server"]                 = nil

ngx.print(res.body)
