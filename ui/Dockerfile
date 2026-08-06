# Build the bundle, then serve it from nginx.
#
# Sprint 11 deploys this application as static objects to S3 behind CloudFront, so this image
# is not the production delivery path. It exists so that the UI can join the Docker Compose
# stack and be reached the way the other services are, and so that a production build is
# exercised somewhere other than one developer's laptop.
#
# The Angular build inlines `src/environments/environment.ts` at compile time. The API origins
# are therefore fixed when the image is built, not when the container starts. To point an
# image at different services, edit that file and rebuild.

FROM node:22-alpine AS build
WORKDIR /app

# Dependencies first, so that a source-only change reuses the cached install layer.
COPY package.json package-lock.json ./
RUN npm ci

COPY . .
RUN npm run build

FROM nginx:1.29-alpine AS serve
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/dist/ui/browser /usr/share/nginx/html
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
