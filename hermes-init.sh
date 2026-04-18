#!/bin/sh
# hermes-init.sh — Runs at container start BEFORE the real entrypoint
# Executes as root, fixes permissions, writes configs, then calls original entrypoint
#
# Writes one .env + config.yaml per HERMES_HOME, one per Ollama Cloud model.
# The per-model wrappers in /usr/local/bin/ (hermes-glm, hermes-gemma, etc.)
# each export their own HERMES_HOME to pick up the right config.

OLLAMA_URL="${OLLAMA_BASE_URL:-https://ollama.com}"

# Format: suffix=model_id (empty suffix means the default /paperclip/.hermes)
# We use '=' as separator because some model IDs contain ':' (e.g. gemma4:31b).
MODELS="
=glm-5.1
-glm=glm-5.1
-minimax=minimax-m2.7
-gemma=gemma4:31b
-qwen=qwen3.5:397b
-gemini=gemini-3-flash-preview
"

echo "$MODELS" | while IFS='=' read -r suffix model; do
    [ -z "$model" ] && continue

    HDIR="/paperclip/.hermes${suffix}"

    # Create required subdirs
    mkdir -p "$HDIR/logs" "$HDIR/sessions"

    # Clean stale sessions + credential cache to prevent "credential pool exhausted"
    rm -rf "$HDIR/sessions/"* 2>/dev/null || true
    rm -f "$HDIR/state.db" "$HDIR/state.db-shm" "$HDIR/state.db-wal" 2>/dev/null || true
    rm -f "$HDIR/auth.json" "$HDIR/auth.lock" 2>/dev/null || true

    # .env — API keys inherited by the hermes process
    cat > "$HDIR/.env" <<EOF
HERMES_MAX_ITERATIONS=90
OLLAMA_BASE_URL=${OLLAMA_URL}
OLLAMA_API_KEY=${OLLAMA_API_KEY}
EOF

    # config.yaml — custom provider pointing at Ollama Cloud, model hard-coded
    cat > "$HDIR/config.yaml" <<EOF
model:
  default: ${model}
  provider: custom
  base_url: ${OLLAMA_URL}/v1
  api_key: ${OLLAMA_API_KEY}
custom_providers:
- name: Ollama.com
  base_url: ${OLLAMA_URL}/v1
  model: ${model}
yolo: true
max_iterations: 90
agent:
  max_turns: 90
EOF

    # Permissions — node user runs hermes via paperclip adapter
    chown -R node:node "$HDIR"
    chmod -R 777 "$HDIR"

    echo "[hermes-init] $HDIR ready (model=$model)"
done

# Also ensure /paperclip/instances is writeable (heartbeat run-logs)
mkdir -p /paperclip/instances/default/data/run-logs
chown -R node:node /paperclip/instances
chmod -R 777 /paperclip/instances

# Symlink /root/.hermes -> /paperclip/.hermes for any caller that checks $HOME
ln -sf /paperclip/.hermes /root/.hermes 2>/dev/null || true
chmod 755 /root 2>/dev/null || true

# Export keys for child processes (hermes spawned by paperclip inherits them)
export OLLAMA_API_KEY="${OLLAMA_API_KEY}"
export OLLAMA_BASE_URL="${OLLAMA_URL}"

echo "[hermes-init] All Hermes homes ready (OLLAMA_BASE_URL=${OLLAMA_URL})"

# Hand off to the REAL Paperclip entrypoint
exec /usr/local/bin/docker-entrypoint.sh "$@"
