#!/bin/bash
# scripts/reload.sh – reload config không downtime
GATEWAY_DIR="$(cd "$(dirname "$0")/.." && pwd)"
openresty -p "$GATEWAY_DIR" -s reload && echo "✅ Reload thành công"
