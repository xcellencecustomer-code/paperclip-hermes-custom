#!/bin/sh
# hermes-init.sh — Runs at container start BEFORE the real entrypoint
# Executes as root, fixes permissions, writes config, then calls original entrypoint

HERMES_DIR="${HERMES_HOME:-/paperclip/.hermes}"

# Create dirs if missing
mkdir -p "$HERMES_DIR/logs" "$HERMES_DIR/sessions"
mkdir -p /paperclip/instances/default/data/run-logs

# Clean stale sessions — prevents Hermes from resuming corrupted/old sessions
rm -rf "$HERMES_DIR/sessions/"* 2>/dev/null || true

# Clean stale credential cache — prevents "credential pool exhausted" errors
rm -f "$HERMES_DIR/state.db" "$HERMES_DIR/state.db-shm" "$HERMES_DIR/state.db-wal" 2>/dev/null || true
rm -f "$HERMES_DIR/auth.json" "$HERMES_DIR/auth.lock" 2>/dev/null || true

# Write .env with API keys from Docker env vars
cat > "$HERMES_DIR/.env" <<EOF
HERMES_MAX_ITERATIONS=90
OLLAMA_BASE_URL=${OLLAMA_BASE_URL:-https://ollama.com}
OLLAMA_API_KEY=${OLLAMA_API_KEY}
OPENROUTER_API_KEY=${OPENROUTER_API_KEY}
EOF

# Write complete Hermes config.yaml with Ollama Cloud + OpenRouter settings
cat > "$HERMES_DIR/config.yaml" <<EOF
inference:
  provider: ollama
  model: glm-5.1
  api_key: ${OLLAMA_API_KEY}
  base_url: ${OLLAMA_BASE_URL:-https://ollama.com}
auxiliary:
  provider: openrouter
  api_key: ${OPENROUTER_API_KEY}
yolo: true
max_iterations: 90
EOF

# Ensure symlink /root/.hermes -> /paperclip/.hermes
ln -sf "$HERMES_DIR" /root/.hermes 2>/dev/null || true
chmod 755 /root 2>/dev/null || true

# Fix ALL permissions — covers any files created by root at runtime
chown -R node:node /paperclip/.hermes
chown -R node:node /paperclip/instances
chmod -R 777 /paperclip/.hermes
chmod -R 777 /paperclip/instances

# Export keys so child processes (hermes spawned by paperclip) inherit them
export OLLAMA_API_KEY="${OLLAMA_API_KEY}"
export OLLAMA_BASE_URL="${OLLAMA_BASE_URL:-https://ollama.com}"
export OPENROUTER_API_KEY="${OPENROUTER_API_KEY}"

echo "[hermes-init] Hermes ready (OLLAMA_BASE_URL=${OLLAMA_BASE_URL}, OPENROUTER=set)"

# Hand off to the REAL Paperclip entrypoint
exec /usr/local/bin/docker-entrypoint.sh "$@"
