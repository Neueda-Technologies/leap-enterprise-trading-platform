# =============================================================================
# Auth stub image.
#
# One stage, because there is nothing to build: no TypeScript, no dependencies,
# one source file. A multi-stage build here would be ceremony.
# =============================================================================
FROM node:20-bookworm-slim

ENV NODE_ENV=production
WORKDIR /app

COPY package.json ./
COPY src ./src

USER node

# 3001 by default, so the stub and the Sprint 8 service can run side by side.
# Compose maps it to 3000, which is where the contract says the auth service
# lives.
EXPOSE 3001

HEALTHCHECK --interval=30s --timeout=3s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:'+(process.env.PORT||3001)+'/auth/me').then(r=>process.exit(r.status===401?0:1)).catch(()=>process.exit(1))"

CMD ["node", "src/server.js"]
