-- lua/middleware/rbac.lua
-- Optimized: pre-compiled patterns, giảm table allocation

local config   = require("config")
local response = require("utils.response")

local _M = {}
function _M.check()
    -- Pre-compile RBAC patterns ở module level (1 lần per worker)
    local _compiled = {}
    for method, rules in pairs(config.rbac) do
        _compiled[method] = {}
        for pattern, permission in pairs(rules) do
            _compiled[method][#_compiled[method] + 1] = {
                pattern    = "^" .. pattern .. "$",
                permission = permission,
                exact      = (not pattern:find("[%(%)%.%+%*%?%[%]%^%$%%]"))  -- không có regex → exact match
            }
        end
    end

    -- Permission check – dùng hash lookup thay vì loop nếu có thể
    local function has_permission(permissions, required)
        if not required then return true end
        -- Build set lần đầu nếu chưa có (cache trong ngx.ctx)
        local ctx = ngx.ctx
        if not ctx.perm_set then
            local set = {}
            for _, p in ipairs(permissions) do
                set[p] = true
            end
            ctx.perm_set = set
        end
        local set = ctx.perm_set
        if set[required] or set["*:*"] then return true end
        -- Wildcard resource:*
        local resource = required:match("^([^:]+):")
        if resource and set[resource .. ":*"] then return true end
        return false
    end

    local function find_required(method, uri)
        local rules = _compiled[method]
        if not rules then return nil end
        for _, rule in ipairs(rules) do
            if rule.exact then
                if uri == rule.pattern:sub(2, -2) then return rule.permission end
            else
                if uri:match(rule.pattern) then return rule.permission end
            end
        end
        return nil
    end

    -- ── Main ──────────────────────────────────────────────────────────────────
    local ctx         = ngx.ctx
    local permissions = ctx.permissions or {}
    local required    = find_required(ngx.req.get_method(), ngx.var.uri)

    if required and not has_permission(permissions, required) then
        response.forbidden(string.format(
            "Cần quyền '%s' để thực hiện %s %s",
            required, ngx.req.get_method(), ngx.var.uri
        ))
    end

end
return _M
