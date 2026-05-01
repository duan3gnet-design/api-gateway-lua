#!/bin/bash
# scripts/start.sh – khởi động gateway

GATEWAY_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OPENRESTY_BIN="${OPENRESTY_BIN:-openresty}"

echo "▶ Khởi động API Gateway từ: $GATEWAY_DIR"

if [ -z "$JWT_SECRET" ] || [ ${#JWT_SECRET} -lt 32 ]; then
    echo "❌ JWT_SECRET phải được set và có ít nhất 32 ký tự"
    exit 1
fi

mkdir -p "$GATEWAY_DIR/logs"
$OPENRESTY_BIN -p "$GATEWAY_DIR" -c nginx.conf

if [ $? -eq 0 ]; then
    echo "✅ Gateway đang chạy tại http://localhost:8080"
else
    echo "❌ Thất bại. Xem logs/error.log"
    exit 1
fi
