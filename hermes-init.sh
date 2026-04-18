#!/bin/sh
# hermes-init.sh — Runs at container start BEFORE the real entrypoint
# Executes as root, fixes permissions, writes config, then calls original entrypoint
#
# Architecture simplifiée (2026-04-18) :
# UN SEUL HERMES_HOME (/paperclip/.hermes) avec provider custom Ollama.
# Le modèle est choisi par AGENT dans l'UI Paperclip (champ "Model") —
# Paperclip passe `-m <model>` à hermes automatiquement via l'adapter.

OLLAMA_URL="${OLLAMA_BASE_URL:-https://ollama.com}"
HDIR="/paperclip/.hermes"

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

# config.yaml — 1 seul config, provider custom Ollama.
# Pas de modèle hardcodé : chaque agent Paperclip définit le sien via le
# champ "Model" de l'UI, et Paperclip passe `-m <model>` à hermes.
# Le `default: glm-5.1` sert uniquement de fallback si hermes est lancé
# sans `-m` (cas standalone, tests manuels).
cat > "$HDIR/config.yaml" <<EOF
model:
  default: glm-5.1
  provider: custom
  base_url: ${OLLAMA_URL}/v1
  api_key: ${OLLAMA_API_KEY}
custom_providers:
- name: Ollama.com
  base_url: ${OLLAMA_URL}/v1
  api_key: ${OLLAMA_API_KEY}
platform_toolsets:
  cli:
    - clarify
    - file
    - memory
    - skills
    - terminal
    - todo
    - web
yolo: true
max_iterations: 90
agent:
  max_turns: 90
EOF

chown -R node:node "$HDIR"
chmod -R 777 "$HDIR"
echo "[hermes-init] $HDIR ready (provider=custom, base_url=${OLLAMA_URL}/v1)"

# Also ensure /paperclip/instances is writeable (heartbeat run-logs)
mkdir -p /paperclip/instances/default/data/run-logs
chown -R node:node /paperclip/instances
chmod -R 777 /paperclip/instances

# Symlink /root/.hermes -> /paperclip/.hermes for any caller that checks $HOME
ln -sf /paperclip/.hermes /root/.hermes 2>/dev/null || true
chmod 755 /root 2>/dev/null || true

# Patch hermes-paperclip-adapter (background-wait — npx installs it after startup).
# 1. VALID_PROVIDERS: add "custom" so provider:custom is accepted.
# 2. SESSION_ID_REGEX_LEGACY: tighten the regex so it doesn't capture plain words
#    like "from" out of error messages ("Use a session ID from a previous CLI run").
#    The original regex /session[_ ](?:id|saved)[:\s]+([a-zA-Z0-9_-]+)/ matches
#    "session ID from" → stores "from" as sessionId → --resume from loop on next run.
#    Fixed regex requires ':' separator and ≥8 chars (real session IDs are ≥20 chars).
(
    TRIES=0
    while [ $TRIES -lt 60 ]; do
        CONSTANTS=$(find /paperclip/.npm -path '*hermes-paperclip-adapter/dist/shared/constants.js' 2>/dev/null | head -1)
        EXECUTE=$(find /paperclip/.npm -path '*hermes-paperclip-adapter/dist/server/execute.js' 2>/dev/null | head -1)
        if [ -n "$CONSTANTS" ] && [ -n "$EXECUTE" ]; then
            # Patch 1: add "custom" to VALID_PROVIDERS whitelist
            sed -i 's/"zai",/"zai","custom",/g' "$CONSTANTS" 2>/dev/null && \
                echo "[hermes-init] Patched VALID_PROVIDERS in $CONSTANTS"
            # Patch 2: fix SESSION_ID_REGEX_LEGACY — the original regex captures plain
            # words like "from" in error messages ("Use a session ID from a previous CLI run")
            # and persists them as sessionId, causing --resume from loops.
            # Python is used because sed cannot reliably escape nested regex syntax in JS.
            python3 - "$EXECUTE" <<'PYEOF'
import sys, re
f = sys.argv[1]
txt = open(f).read()
# Replace the legacy regex: require ':' separator + min 8 chars (real IDs are 20+ chars)
patched = re.sub(
    r'SESSION_ID_REGEX_LEGACY\s*=\s*/[^/]+/i',
    'SESSION_ID_REGEX_LEGACY = /session[_ ](?:id|saved):\\s+([a-zA-Z0-9_-]{8,})/i',
    txt
)
if patched != txt:
    open(f, 'w').write(patched)
    print(f'[hermes-init] Patched SESSION_ID_REGEX_LEGACY in {f}')
else:
    print(f'[hermes-init] SESSION_ID_REGEX_LEGACY already patched or not found in {f}')
PYEOF
            break
        fi
        TRIES=$((TRIES + 1))
        sleep 2
    done
) &

# Export keys for child processes (hermes spawned by paperclip inherits them)
export OLLAMA_API_KEY="${OLLAMA_API_KEY}"
export OLLAMA_BASE_URL="${OLLAMA_URL}"

echo "[hermes-init] Hermes home ready (OLLAMA_BASE_URL=${OLLAMA_URL})"

# Hand off to the REAL Paperclip entrypoint
exec /usr/local/bin/docker-entrypoint.sh "$@"
