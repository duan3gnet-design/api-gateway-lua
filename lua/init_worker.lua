-- lua/init_worker.lua
-- Chỉ chạy trong init_worker_by_lua_file (mỗi worker process)
-- Cosocket hoạt động bình thường ở đây → có thể query DB

-- Chỉ worker 0 load routes để tránh N workers cùng query DB một lúc
-- Các workers khác đọc từ lua_shared_dict (shared giữa tất cả workers)
if ngx.worker.id() ~= 0 then return end

local route_store = require("store.route_store")

ngx.timer.at(0, function(premature)
    if premature then return end

    local ok, err =  route_store.reload()
    
    if not ok then
        ngx.log(ngx.ERR, "[init_worker] Load routes thất bại: ", err)
    else
        ngx.log(ngx.INFO, "[init_worker] Routes loaded OK – ", route_store.info().route_count, " routes")
    end

end)
