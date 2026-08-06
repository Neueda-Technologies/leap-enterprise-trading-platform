# =============================================================================
# Auth service image, multi-stage.
#
# The build stage needs a compiler: argon2 is a native module, and where no
# prebuilt binary matches the platform it is compiled from source. The runtime
# stage needs none of that, so it starts from a clean base and receives only
# node_modules, the compiled JavaScript and the migration file. That is the
# point of the split: the shipped image has no compiler, no TypeScript and no
# test tooling in it.
# =============================================================================

# -----------------------------------------------------------------------------
# Stage 1: install, compile, drop the development dependencies
# -----------------------------------------------------------------------------
FROM node:20-bookworm-slim AS build

WORKDIR /app

RUN apt-get update \
 && apt-get install -y --no-install-recommends python3 make g++ \
 && rm -rf /var/lib/apt/lists/*

# Dependencies are copied and installed before the source, so that a change to a
# source file does not invalidate the cached install layer.
COPY package.json package-lock.json ./
RUN npm ci

COPY tsconfig.json tsconfig.build.json nest-cli.json ./
COPY src ./src

RUN npm run build \
 && npm prune --omit=dev

# -----------------------------------------------------------------------------
# Stage 2: runtime
# -----------------------------------------------------------------------------
FROM node:20-bookworm-slim AS runtime

ENV NODE_ENV=production
WORKDIR /app

COPY --from=build /app/node_modules ./node_modules
COPY --from=build /app/dist ./dist
COPY package.json ./
COPY migrations ./migrations

# The node user ships with the base image. A process that does not need root
# should not have it, and this one only opens a socket and talks to Postgres.
USER node

EXPOSE 3000

# The service exposes only the four contract routes, so the check uses the
# generated OpenAPI document rather than a health endpoint the contract does not
# describe.
HEALTHCHECK --interval=30s --timeout=3s --start-period=20s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:'+(process.env.PORT||3000)+'/docs/json').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"

CMD ["node", "dist/main.js"]
