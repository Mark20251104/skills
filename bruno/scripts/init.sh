#!/usr/bin/env bash
# Bruno collection 初始化脚本
# 用法：./init.sh [project-root]
# 不传参数时使用当前目录
set -euo pipefail

ROOT="${1:-$(pwd)}"
TARGET="$ROOT/bruno-collection"

if [[ -d "$TARGET" ]]; then
  echo "ERROR: $TARGET 已存在，终止以避免覆盖" >&2
  exit 1
fi

PROJECT_NAME="$(basename "$ROOT")"

mkdir -p "$TARGET/environments"

cat > "$TARGET/bruno.json" <<EOF
{
  "version": "1",
  "name": "$PROJECT_NAME",
  "type": "collection",
  "ignore": ["node_modules", ".git"]
}
EOF

cat > "$TARGET/environments/local.bru" <<'EOF'
vars {
  baseUrl: http://localhost:8080
  token:
}
EOF

cat > "$TARGET/environments/dev.bru" <<'EOF'
vars {
  baseUrl: http://10.80.0.25:7001
  token:
}
EOF

cat > "$TARGET/environments/sit.bru" <<'EOF'
vars {
  baseUrl: http://10.80.1.22:7001
  token:
}
EOF

cat > "$TARGET/.gitignore" <<'EOF'
# 本地敏感凭证（如需共享请改用 secrets 机制）
environments/*.local.bru
EOF

echo "OK: 已创建 $TARGET"
