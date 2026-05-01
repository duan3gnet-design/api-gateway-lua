-- lua/utils/logger.lua
-- Thin wrapper quanh ngx.log để thống nhất format

local _M = {}

local LEVELS = { debug = true, info = true, warn = true, error = true }

local function _log(level, msg)
    if level == "debug" then
        ngx.log(ngx.DEBUG, msg)
    elseif level == "info" then
        ngx.log(ngx.INFO, msg)
    elseif level == "warn" then
        ngx.log(ngx.WARN, msg)
    else
        ngx.log(ngx.ERR, msg)
    end
end

function _M.debug(msg) _log("debug", msg) end
function _M.info(msg)  _log("info",  msg) end
function _M.warn(msg)  _log("warn",  msg) end
function _M.error(msg) _log("error", msg) end

-- Log với context request
function _M.req(level, msg)
    local ctx = string.format("[%s %s] %s",
        ngx.req.get_method(),
        ngx.var.request_uri,
        msg
    )
    _log(level, ctx)
end

return _M
