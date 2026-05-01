# API Gateway – Lua / OpenResty

API Gateway nhẹ, hiệu năng cao chạy trên **OpenResty (Nginx + LuaJIT)**.

## Tính năng

| Feature | Chi tiết |
|---|---|
| **JWT Auth** | Verify HS256, check exp/nbf/iss, blacklist (revoke) |
| **RBAC** | Permission dạng `resource:action` đọc từ JWT payload |
| **Rate Limiting** | Fixed window per-IP hoặc per-user, header `X-RateLimit-*` |
| **Routing** | Auth Service (public) + Resource Service (protected) |
| **Security Headers** | `X-Frame-Options`, `X-XSS-Protection`, ẩn `Server` header |
| **Admin API** | Stats, blacklist token, reset rate limit (chỉ localhost) |
| **Health Check** | `GET /health` |

## Cấu trúc

```
api-gateway-lua/
├── nginx.conf                  # Entry point OpenResty
├── conf/
│   └── proxy_headers.conf      # Header chung cho upstream
├── lua/
│   ├── init.lua                # Khởi động, validate config
│   ├── config.lua              # Toàn bộ cấu hình
│   ├── middleware/
│   │   ├── auth.lua            # Xác thực JWT
│   │   ├── rbac.lua            # Kiểm tra permission
│   │   ├── rate_limiter.lua    # Rate limiting
│   │   └── response_header.lua # Security response headers
│   ├── utils/
│   │   ├── jwt.lua             # JWT verify (thuần Lua, HS256)
│   │   ├── logger.lua          # Wrapper ngx.log
│   │   └── response.lua        # JSON error helper
│   └── admin/
│       └── handler.lua         # Admin API
└── logs/                       # access.log, error.log
```

## Cài đặt

### 1. Cài OpenResty

**Windows (WSL2 Ubuntu):**
```bash
sudo apt-get install -y software-properties-common
sudo add-apt-repository -y "deb http://openresty.org/package/ubuntu $(lsb_release -sc) main"
sudo apt-get update
sudo apt-get install -y openresty
```

**Docker (khuyến nghị):**
```bash
docker run -d --name api-gateway \
  -p 8080:8080 \
  -v $(pwd):/usr/local/openresty/nginx \
  -e JWT_SECRET=your-super-secret-key-minimum-32-chars \
  openresty/openresty:alpine-fat
```

### 2. Cài dependencies Lua

```bash
# resty.hmac (dùng để verify JWT HS256)
opm get jkeys089/lua-resty-hmac

# hoặc dùng luarocks
luarocks install lua-resty-hmac
```

### 3. Cấu hình environment

| Biến | Mặc định | Mô tả |
|---|---|---|
| `JWT_SECRET` | *(cần đặt)* | Secret HS256, ≥ 32 ký tự |
| `JWT_ISSUER` | `auth-service` | Issuer check trong payload |
| `RATE_LIMIT_MAX` | `100` | Max request per window |
| `RATE_LIMIT_WINDOW` | `60` | Window tính bằng giây |
| `LOG_LEVEL` | `info` | debug / info / warn / error |

### 4. Khởi động

```bash
# Chạy OpenResty với nginx.conf trong thư mục này
openresty -p /path/to/api-gateway-lua -c nginx.conf

# Reload (không downtime)
openresty -p /path/to/api-gateway-lua -s reload

# Stop
openresty -p /path/to/api-gateway-lua -s stop
```

## Test nhanh

```bash
# Health check
curl http://localhost:8080/health

# Auth (public)
curl -X POST http://localhost:8080/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"test","password":"test"}'

# Protected route (cần JWT)
curl http://localhost:8080/api/resource/items \
  -H "Authorization: Bearer <your_jwt_token>"

# Admin – blacklist token
curl -X POST http://localhost:8080/admin/blacklist \
  -H "Content-Type: application/json" \
  -d '{"jti":"abc123","ttl":3600}'

# Admin – stats
curl http://localhost:8080/admin/stats
```

## Tích hợp với Spring Boot project

Gateway này hoạt động như tầng front-door trước `auth-service` (`:8081`) và `resource-service` (`:8082`).

```
Client → OpenResty Gateway :8080
           ├── /api/auth/*    → auth-service     :8081
           └── /api/resource/* → resource-service :8082
```

JWT được issue bởi `auth-service` (Spring Boot + JJWT), gateway chỉ verify – không cần gọi lại auth-service cho mỗi request.

## Mở rộng

- **Circuit Breaker**: Dùng `lua-resty-circuit-breaker` hoặc tích hợp Resilience4j từ Spring Cloud Gateway nếu muốn chuyển sang Java.
- **Redis Rate Limit**: Thay `lua_shared_dict` bằng Redis để hỗ trợ multi-instance.
- **Metrics**: Export Prometheus metrics qua `lua-resty-prometheus`.
