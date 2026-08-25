# syntax=docker/dockerfile:1.7

ARG NODE_IMAGE=node:24-slim
# pnpm-lock.yaml uses lockfileVersion 9.x, so we pin to pnpm v9 to keep behavior stable.
ARG PNPM_VERSION=9.15.9

# ============================================
# Stage 0: Base (tooling)
# ============================================
FROM ${NODE_IMAGE} AS base

ARG PNPM_VERSION

WORKDIR /app

# Install pnpm (pinned) with a reusable npm download cache.
RUN --mount=type=cache,id=sealos-tty-bridge-npm-cache,target=/root/.npm,sharing=locked \
    npm install -g "pnpm@${PNPM_VERSION}" \
    && pnpm config set store-dir /pnpm/store

# ============================================
# Stage 1: Dependencies (deterministic + cache-mount)
# ============================================
FROM base AS deps

# Copy workspace manifests only (maximizes cache hit rate).
COPY package.json pnpm-workspace.yaml pnpm-lock.yaml ./
COPY packages/protocol-client/package.json ./packages/protocol-client/

# Populate pnpm store into a dedicated cache, then install fully offline.
# This makes dependency retrieval largely independent of Docker layer cache.
RUN --mount=type=cache,id=sealos-tty-bridge-pnpm-store,target=/pnpm/store,sharing=locked \
    pnpm fetch
RUN --mount=type=cache,id=sealos-tty-bridge-pnpm-store,target=/pnpm/store,sharing=locked \
    pnpm install --offline --frozen-lockfile

# ============================================
# Stage 2: Build
# ============================================
FROM deps AS build

# Copy source code
COPY . .

# Build the protocol-client package (generates dist/*.d.ts)
RUN pnpm run build

# Strip devDependencies after build; runtime will copy these node_modules.
RUN CI=true pnpm prune --prod

# ============================================
# Stage 3: Runtime (no network install)
# ============================================
FROM ${NODE_IMAGE} AS runtime

WORKDIR /app

# Set production environment
ENV NODE_ENV=production
ENV PORT=3000

# Copy production dependencies + workspace package output
COPY --from=build /app/package.json ./package.json
COPY --from=build /app/node_modules ./node_modules
COPY --from=build /app/packages/protocol-client ./packages/protocol-client

# Copy app source code (executed directly with --experimental-strip-types)
COPY --from=build /app/src ./src

# Use non-root user
USER node

# Expose port
EXPOSE 3000

# Health check without curl
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
    CMD node -e "require('http').get('http://127.0.0.1:3000/', (r) => process.exit(r.statusCode < 500 ? 0 : 1)).on('error', () => process.exit(1))"

# Start application using Node.js experimental strip-types
CMD ["node", "--experimental-strip-types", "src/index.ts"]
