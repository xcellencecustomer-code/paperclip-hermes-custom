FROM ghcr.io/paperclipai/paperclip:latest

# Install python3-venv (Debian 13 / trixie)
RUN apt-get update && apt-get install -y --no-install-recommends python3-venv \
    && rm -rf /var/lib/apt/lists/*

# Install Hermes Agent in a persistent venv
RUN python3 -m venv /opt/hermes-venv \
    && /opt/hermes-venv/bin/pip install --no-cache-dir \
       https://github.com/NousResearch/hermes-agent/archive/refs/heads/main.tar.gz

# Single hermes wrapper — no per-model wrappers.
# The model is chosen per-agent in the Paperclip UI ("Model" field),
# and Paperclip passes `-m <model>` to hermes via the adapter.
RUN printf '#!/bin/sh\nexec /opt/hermes-venv/bin/hermes --yolo "$@"\n' > /usr/local/bin/hermes \
    && chmod +x /usr/local/bin/hermes

# Pre-configure single Hermes directory (config.yaml written at runtime by hermes-init.sh)
RUN mkdir -p /paperclip/.hermes/logs /paperclip/.hermes/sessions \
    && ln -sf /paperclip/.hermes /root/.hermes \
    && chmod 755 /root

# Pre-create Paperclip instances directory + permissions on Hermes home
RUN mkdir -p /paperclip/instances/default/data/run-logs \
    && chown -R node:node /paperclip/.hermes /paperclip/instances \
    && chmod -R 777 /paperclip/.hermes

# Init script: runs as root, fixes perms, writes config.yaml + .env,
# patches hermes-paperclip-adapter VALID_PROVIDERS (dynamic, in background),
# then execs the real Paperclip entrypoint.
COPY hermes-init.sh /usr/local/bin/hermes-init.sh
RUN chmod +x /usr/local/bin/hermes-init.sh

ENTRYPOINT ["hermes-init.sh"]
CMD ["node", "--import", "./server/node_modules/tsx/dist/loader.mjs", "server/dist/index.js"]
