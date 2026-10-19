# Isolated runner for Codex: sees only a clean clone of one branch, never .env or any deploy token.
FROM node:22-bookworm
RUN apt-get update && apt-get install -y --no-install-recommends git ca-certificates ripgrep \
  && rm -rf /var/lib/apt/lists/* \
  && npm install -g @openai/codex@0.163.0
ENV CODEX_HOME=/codex-home
WORKDIR /work
