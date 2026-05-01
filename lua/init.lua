-- lua/init.lua
-- Chạy một lần khi OpenResty khởi động (init_by_lua_file)

local config = require("config")
local logger  = require("utils.logger")

-- Validate JWT secret
assert(
    config.jwt.secret and #config.jwt.secret >= 32,
    "[INIT] jwt.secret phải có ít nhất 32 ký tự!"
)

logger.info("[INIT] ✅ API Gateway khởi động thành công")
logger.info(string.format("[INIT]    JWT issuer    : %s", config.jwt.issuer))
logger.info(string.format("[INIT]    Rate limit    : %d req / %ds",
    config.rate_limit.max_requests, config.rate_limit.window_seconds))
