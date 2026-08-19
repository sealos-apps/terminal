FROM node:20.20.2-alpine AS base

ENV PNPM_HOME="/pnpm"
ENV PATH="$PNPM_HOME:$PATH"
WORKDIR /app

FROM base AS deps

RUN apk add --no-cache libc6-compat \
  && corepack enable \
  && corepack prepare pnpm@8.9.0 --activate

COPY package.json pnpm-lock.yaml ./
RUN --mount=type=cache,id=terminal-pnpm,target=/pnpm/store pnpm fetch

FROM deps AS builder

ENV NEXT_TELEMETRY_DISABLED=1

COPY . .
RUN --mount=type=cache,id=terminal-pnpm,target=/pnpm/store \
  pnpm install --offline --frozen-lockfile \
  && pnpm run build

FROM node:20.20.2-alpine AS runner

ENV NODE_ENV=production
ENV NEXT_TELEMETRY_DISABLED=1
ENV PORT=3000

RUN addgroup --system --gid 1001 nodejs \
  && adduser --system --uid 1001 nextjs \
  && apk add --no-cache dumb-init ca-certificates

WORKDIR /app
COPY --from=builder /app/public ./public
COPY --from=builder --chown=nextjs:nodejs /app/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejs /app/.next/static ./.next/static

USER nextjs
EXPOSE 3000
ENTRYPOINT ["dumb-init", "--"]
CMD ["node", "server.js"]
