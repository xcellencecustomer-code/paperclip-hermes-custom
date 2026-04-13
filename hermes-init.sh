#!/bin/sh
# hermes-init.sh — Runs at container start BEFORE the real entrypoint
# Executes as root, fixes permissions, writes config, then calls original entrypoint

HERMES_DIR="${HERMES_HOME:-/paperclip/.hermes}"

# Create dirs if missing
mkdir -p "$HERMES_DIR/logs" "$HERMES_DIR/sessions"
mkdir -p /paperclip/instances/default/data/run-logs

# Write .env with API keys from Docker env vars
cat > "$HERMES_DIR/.env" <<EOF
HERMES_MAX_ITERATIONS=90
OLLAMA_BASE_URL=${OLLAMA_BASE_URL:-https://ollama.com}
OLLAMA_API_KEY=${OLLAMA_API_KEY}
EOF

# Patch config.yaml with correct API key if it exists
# This fixes the case where hermes setup was run with a wrong key
if [ -f "$HERMES_DIR/config.yaml" ] && [ -n "$OLLAMA_API_KEY" ]; then
    sed -i "s|api_key:.*|api_key: ${OLLAMA_API_KEY}|g" "$HERMES_DIR/config.yaml"
fi

# Ensure symlink /root/.hermes -> /paperclip/.hermes
ln -sf "$HERMES_DIR" /root/.hermes 2>/dev/null || true
chmod 755 /root 2>/dev/null || true

# Fix ALL permissions — covers any files created by root at runtime
chown -R node:node /paperclip/.hermes
chown -R node:node /paperclip/instances
chmod -R 777 /paperclip/.hermes
chmod -R 777 /paperclip/instances

echo "[hermes-init] Hermes ready (OLLAMA_BASE_URL=${OLLAMA_BASE_URL})"

# Hand off to the REAL Paperclip entrypoint
exec /usr/local/bin/docker-entrypoint.sh "$@"
