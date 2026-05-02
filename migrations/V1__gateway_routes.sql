-- migrations/V1__gateway_routes.sql

CREATE TABLE IF NOT EXISTS gateway_upstreams (
    id         SERIAL PRIMARY KEY,
    name       VARCHAR(100) NOT NULL UNIQUE,
    -- [{"host":"127.0.0.1","port":8081,"weight":1}, ...]
    targets    JSONB   NOT NULL,
    enabled    BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS gateway_routes (
    id                SERIAL  PRIMARY KEY,
    path_prefix       VARCHAR(255) NOT NULL UNIQUE, -- vd: /api/orders/
    upstream_name     VARCHAR(100) NOT NULL REFERENCES gateway_upstreams(name),

    -- Auth
    auth_required     BOOLEAN NOT NULL DEFAULT TRUE,

    -- RBAC: map method → permission yêu cầu
    -- {"GET":"orders:READ","POST":"orders:CREATE","DELETE":"orders:DELETE"}
    -- NULL = không check RBAC (chỉ cần auth hợp lệ)
    rbac_permissions  JSONB DEFAULT NULL,

    -- Rate limit riêng cho từng route
    rate_limit_max    INTEGER NOT NULL DEFAULT 100,
    rate_limit_window INTEGER NOT NULL DEFAULT 60,

    -- Strip path prefix khi proxy xuống upstream
    strip_prefix      BOOLEAN NOT NULL DEFAULT FALSE,

    enabled           BOOLEAN NOT NULL DEFAULT TRUE,
    created_at        TIMESTAMPTZ DEFAULT NOW(),
    updated_at        TIMESTAMPTZ DEFAULT NOW()
);

-- ── Seed data ─────────────────────────────────────────────────────────────
INSERT INTO gateway_upstreams (name, targets) VALUES
    ('auth-service',     '[{"host":"host.docker.internal","port":8081,"weight":1}]'),
    ('resource-service', '[{"host":"host.docker.internal","port":8082,"weight":1}]');

INSERT INTO gateway_routes
    (path_prefix, upstream_name, auth_required, rbac_permissions, rate_limit_max, rate_limit_window)
VALUES
    -- Auth service: public hoàn toàn
    ('/api/auth/', 'auth-service', FALSE, NULL, 200, 60),

    -- Resource service: cần JWT + RBAC per method
    ('/api/resource/items', 'resource-service', TRUE,
     '{"GET":"items:READ","POST":"items:CREATE","PUT":"items:UPDATE","DELETE":"items:DELETE"}',
     100, 60),

    -- Admin resource: cần JWT, rate limit thấp hơn
    ('/api/resource/admin', 'resource-service', TRUE,
     '{"GET":"admin:READ","DELETE":"admin:DELETE"}',
     20, 60);
