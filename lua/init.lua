-- lua/init.lua
-- Chỉ chạy trong init_by_lua_file (master process, trước khi fork workers)
-- KHÔNG được dùng cosocket, KHÔNG được query DB ở đây

local config = require("config")

assert(
    config.jwt.secret and #config.jwt.secret >= 32,
    "[INIT] jwt.secret phải có ít nhất 32 ký tự!"
)

ngx.log(ngx.INFO, "[INIT] API Gateway config OK")
