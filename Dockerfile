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
