FROM ghcr.io/paperclipai/paperclip:latest

# Install python3-venv (Debian 13 / trixie)
RUN apt-get update && apt-get install -y --no-install-recommends python3-venv \
    && rm -rf /var/lib/apt/lists/*

# Install Hermes Agent in a persistent venv
RUN python3 -m venv /opt/hermes-venv \
    && /opt/hermes-venv/bin/pip install --no-cache-dir \
       https://github.com/NousResearch/hermes-agent/archive/refs/heads/main.tar.gz

# Yolo wrapper so Paperclip adapter never blocks on confirmation prompts
RUN printf '#!/bin/sh\nexec /opt/hermes-venv/bin/hermes --yolo "$@"\n' > /usr/local/bin/hermes \
    && chmod +x /usr/local/bin/hermes

# Pre-configure Hermes directories and config
RUN mkdir -p /paperclip/.hermes/logs /paperclip/.hermes/sessions /paperclip/.hermes/bin \
    && printf 'inference:\n  provider: ollama\n  model: glm-5.1\nyolo: true\n' > /paperclip/.hermes/config.yaml \
    && ln -sf /paperclip/.hermes /root/.hermes \
    && chmod 755 /root

# Pre-create Paperclip instances directory
RUN mkdir -p /paperclip/instances/default/data/run-logs \
    && chown -R node:node /paperclip/.hermes /paperclip/instances \
    && chmod -R 777 /paperclip/.hermes

# Init script: runs as root, fixes perms, writes .env, then calls real entrypoint
COPY hermes-init.sh /usr/local/bin/hermes-init.sh
RUN chmod +x /usr/local/bin/hermes-init.sh

# Override ENTRYPOINT with our wrapper that calls the real one after init
# hermes-init.sh does: fix perms → write .env → exec docker-entrypoint.sh "$@"
ENTRYPOINT ["hermes-init.sh"]
