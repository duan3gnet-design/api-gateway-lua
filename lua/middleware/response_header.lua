-- lua/middleware/response_header.lua
-- header_filter_by_lua_file: thêm/xoá response header

-- Thêm security headers
ngx.header["X-Gateway"]               = "lua-gateway/1.0"
ngx.header["X-Content-Type-Options"]  = "nosniff"
ngx.header["X-Frame-Options"]         = "DENY"
ngx.header["X-XSS-Protection"]        = "1; mode=block"
ngx.header["Referrer-Policy"]         = "no-referrer"

-- Xoá header lộ thông tin server
ngx.header["Server"]                  = nil
ngx.header["X-Powered-By"]            = nil
