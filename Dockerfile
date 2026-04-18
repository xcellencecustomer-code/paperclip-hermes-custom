FROM ghcr.io/paperclipai/paperclip:latest

# Install python3-venv (Debian 13 / trixie)
RUN apt-get update && apt-get install -y --no-install-recommends python3-venv \
    && rm -rf /var/lib/apt/lists/*

# Install Hermes Agent in a persistent venv
RUN python3 -m venv /opt/hermes-venv \
    && /opt/hermes-venv/bin/pip install --no-cache-dir \
       https://github.com/NousResearch/hermes-agent/archive/refs/heads/main.tar.gz

# Per-model wrappers: each exports its own HERMES_HOME so it picks up a
# dedicated config.yaml (written at runtime by hermes-init.sh). The generic
# `hermes` keeps the default /paperclip/.hermes for backward compatibility.
# Use a per-model wrapper as the "Command" field of a Paperclip Hermes adapter
# to bind that adapter to a specific Ollama Cloud model.
RUN set -eu; \
    printf '#!/bin/sh\nexec /opt/hermes-venv/bin/hermes --yolo "$@"\n' > /usr/local/bin/hermes; \
    chmod +x /usr/local/bin/hermes; \
    for name in hermes-glm hermes-minimax hermes-gemma hermes-qwen hermes-gemini; do \
        printf '#!/bin/sh\nexport HERMES_HOME=/paperclip/.%s\nexec /opt/hermes-venv/bin/hermes --yolo "$@"\n' "$name" > "/usr/local/bin/$name"; \
        chmod +x "/usr/local/bin/$name"; \
    done

# Patch hermes-paperclip-adapter: add "custom" to VALID_PROVIDERS whitelist
# Without this, the adapter rejects custom providers and auto-infers based on model name
RUN sed -i 's/"zai",/"zai","custom",/g' /paperclip/server/dist/adapters/hermes-local/shared/constants.js || true

# Pre-configure Hermes directories (config.yaml written at runtime by hermes-init.sh)
# One HOME per model — matches the per-model wrappers above.
RUN for d in .hermes .hermes-glm .hermes-minimax .hermes-gemma .hermes-qwen .hermes-gemini; do \
        mkdir -p "/paperclip/$d/logs" "/paperclip/$d/sessions" "/paperclip/$d/bin"; \
    done \
    && ln -sf /paperclip/.hermes /root/.hermes \
    && chmod 755 /root

# Pre-create Paperclip instances directory + permissions on all Hermes homes
RUN mkdir -p /paperclip/instances/default/data/run-logs \
    && for d in .hermes .hermes-glm .hermes-minimax .hermes-gemma .hermes-qwen .hermes-gemini; do \
        chown -R node:node "/paperclip/$d"; \
        chmod -R 777 "/paperclip/$d"; \
    done \
    && chown -R node:node /paperclip/instances

# Init script: runs as root, fixes perms, writes .env, then calls real entrypoint
COPY hermes-init.sh /usr/local/bin/hermes-init.sh
RUN chmod +x /usr/local/bin/hermes-init.sh

# Override ENTRYPOINT with our wrapper that calls the real one after init
# hermes-init.sh does: fix perms → write .env → exec docker-entrypoint.sh "$@"
ENTRYPOINT ["hermes-init.sh"]
CMD ["node", "--import", "./server/node_modules/tsx/dist/loader.mjs", "server/dist/index.js"]
