# Isolated runner for Codex: sees only a clean clone of one branch, never .env or any deploy token.
# Swift toolchain so Codex (and Claude) can build and test the MealPlannerCore package on Linux.
FROM swift:6.2-bookworm
ARG NODE_VERSION=22.20.0
RUN apt-get update && apt-get install -y --no-install-recommends git ca-certificates ripgrep curl xz-utils \
  && rm -rf /var/lib/apt/lists/* \
  && curl -fsSL "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-x64.tar.xz" \
     | tar -xJ -C /usr/local --strip-components=1 \
  && npm install -g @openai/codex@0.163.0 && npm cache clean --force
ENV CODEX_HOME=/codex-home
WORKDIR /work
