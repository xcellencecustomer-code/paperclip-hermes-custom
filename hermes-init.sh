#!/bin/sh
# hermes-init.sh — Runs at container start as user node (via gosu)
# Writes Hermes .env from Docker environment variables
# This avoids manual terminal configuration after each deploy

HERMES_DIR="${HERMES_HOME:-/paperclip/.hermes}"

# Create dirs if missing
mkdir -p "$HERMES_DIR/logs" "$HERMES_DIR/sessions"

# Write .env with API keys from Docker env vars
cat > "$HERMES_DIR/.env" <<EOF
HERMES_MAX_ITERATIONS=90
OLLAMA_BASE_URL=${OLLAMA_BASE_URL:-https://ollama.com}
OLLAMA_API_KEY=${OLLAMA_API_KEY}
EOF

# Ensure symlink /root/.hermes -> /paperclip/.hermes exists
# (may be lost if /root is recreated)
if [ ! -L /root/.hermes ] 2>/dev/null; then
    ln -sf "$HERMES_DIR" /root/.hermes 2>/dev/null || true
fi

echo "[hermes-init] Hermes config ready at $HERMES_DIR"
