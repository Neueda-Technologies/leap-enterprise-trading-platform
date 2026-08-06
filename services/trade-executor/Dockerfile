# Stage 1: build. The build image carries Maven, a full JDK and the whole dependency tree, and
# none of that belongs in the image that runs in production.
FROM maven:3.9-eclipse-temurin-21 AS build

WORKDIR /build

# Copy the descriptor first and resolve dependencies on its own layer. Docker then reuses that
# layer on every build that changes only source code, which is almost every build.
COPY pom.xml ./
RUN mvn -B -q dependency:go-offline

COPY src ./src
RUN mvn -B -q -DskipTests package

# Stage 2: run. A JRE, the jar and nothing else.
FROM eclipse-temurin:21-jre-alpine

# A container that runs as root gives an attacker who escapes the JVM a root shell in the
# namespace. Create an unprivileged user and switch to it before the entrypoint.
RUN addgroup -S executor && adduser -S executor -G executor

WORKDIR /app
COPY --from=build /build/target/trade-executor-*.jar /app/trade-executor.jar
USER executor

EXPOSE 8082

# The container is healthy when Spring reports it healthy, which includes the datasource. A
# process-liveness check would call a service with a dead connection pool healthy.
HEALTHCHECK --interval=15s --timeout=3s --start-period=40s --retries=3 \
    CMD wget -qO- http://localhost:8082/actuator/health | grep -q '"status":"UP"' || exit 1

# No API key, no database password and no bootstrap server is baked in. Everything comes from the
# environment at run time.
ENTRYPOINT ["java", "-XX:MaxRAMPercentage=75", "-jar", "/app/trade-executor.jar"]
