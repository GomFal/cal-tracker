FROM oven/bun:1 AS build

WORKDIR /app

COPY package.json bun.lock ./
COPY apps/backend/package.json apps/backend/package.json
COPY packages/contracts/package.json packages/contracts/package.json
RUN bun install --frozen-lockfile

COPY tsconfig.base.json ./
COPY packages/contracts packages/contracts
COPY apps/backend apps/backend
COPY apps/mobile/lib/l10n apps/mobile/lib/l10n
COPY infra/db/migrations infra/db/migrations
COPY infra/db/drizzle infra/db/drizzle

RUN bun run typecheck
RUN bun run build
RUN bun install --frozen-lockfile --production

FROM oven/bun:1 AS runtime

ENV NODE_ENV=production
ENV PORT=3000

WORKDIR /app

COPY --from=build /app/package.json /app/bun.lock ./
COPY --from=build /app/node_modules ./node_modules
COPY --from=build /app/packages/contracts/package.json ./packages/contracts/package.json
COPY --from=build /app/packages/contracts/dist ./packages/contracts/dist
COPY --from=build /app/apps/backend/package.json ./apps/backend/package.json
COPY --from=build /app/apps/backend/dist ./apps/backend/dist
COPY --from=build /app/apps/mobile/lib/l10n ./apps/mobile/lib/l10n
COPY --from=build /app/infra/db/migrations ./infra/db/migrations
COPY --from=build /app/infra/db/drizzle ./infra/db/drizzle

WORKDIR /app/apps/backend

USER bun
EXPOSE 3000

HEALTHCHECK --interval=15s --timeout=5s --start-period=20s --retries=5 CMD bun -e "fetch('http://127.0.0.1:' + (process.env.PORT || '3000') + '/v1/health').then((response) => process.exit(response.ok ? 0 : 1)).catch(() => process.exit(1))"

CMD ["bun", "dist/src/index.js"]
