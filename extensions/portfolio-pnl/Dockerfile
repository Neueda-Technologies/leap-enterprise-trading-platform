# Portfolio and P&L service. Multi-stage build: compile with the full JDK and Maven,
# ship only the JRE and the built jar. The build stage alone is roughly 400 MB with
# Maven's own dependencies; none of that belongs in the runtime image.

FROM eclipse-temurin:21-jdk-jammy AS build
WORKDIR /build

# Dependencies first, so a source-only change does not re-download the internet.
COPY pom.xml .
RUN --mount=type=cache,target=/root/.m2 mvn -B -q dependency:go-offline

COPY src ./src
RUN --mount=type=cache,target=/root/.m2 mvn -B -q -DskipTests package \
    && mv target/portfolio-pnl-service.jar target/app.jar

FROM eclipse-temurin:21-jre-jammy AS runtime
WORKDIR /app

# curl is not in the base JRE image; it is here only for HEALTHCHECK.
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/*

# Least privilege: the service does not need to run as root.
RUN groupadd --system portfolio && useradd --system --gid portfolio portfolio
USER portfolio

COPY --from=build /build/target/app.jar ./app.jar

EXPOSE 8081

# Fauxnance key and JWT secret arrive as environment variables at run time, never
# baked into the image. See README.md for the full list.
ENTRYPOINT ["java", "-jar", "/app/app.jar"]

HEALTHCHECK --interval=30s --timeout=3s --start-period=30s --retries=3 \
    CMD curl -sf http://localhost:8081/health | grep -q '"status"' || exit 1
