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
# /paperclip/.hermes is the real config dir, symlinked from /root/.hermes
# Both root and node user access the same files
RUN mkdir -p /paperclip/.hermes/logs /paperclip/.hermes/sessions /paperclip/.hermes/bin \
    && printf 'inference:\n  provider: ollama\n  model: glm-5.1\nyolo: true\n' > /paperclip/.hermes/config.yaml \
    && ln -sf /paperclip/.hermes /root/.hermes \
    && chmod 755 /root

# Pre-create Paperclip instances directory
RUN mkdir -p /paperclip/instances/default/data/run-logs

# Set ownership for node user (Paperclip runs as node via gosu)
RUN chown -R node:node /paperclip/.hermes /paperclip/instances \
    && chmod -R 777 /paperclip/.hermes

# Init script: writes API keys from env vars into Hermes .env at container start
# This runs BEFORE the original entrypoint hands off to gosu node
COPY hermes-init.sh /usr/local/bin/hermes-init.sh
RUN chmod +x /usr/local/bin/hermes-init.sh

# DO NOT override ENTRYPOINT — it breaks gosu/Paperclip chain
# Instead, the original entrypoint runs: docker-entrypoint.sh → gosu node → CMD
# We prepend our init to CMD so it runs as node
CMD ["sh", "-c", "/usr/local/bin/hermes-init.sh && node dist/index.js"]
