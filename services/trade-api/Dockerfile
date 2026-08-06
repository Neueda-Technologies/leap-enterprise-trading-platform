# Trade REST API image.
#
# Build context is the `services` directory, not this one, because the service depends on the
# trading-engine module and Docker cannot copy from above its context:
#
#   docker build -f services/trade-api/Dockerfile -t trade-api:1.0.0 services
#
# In docker-compose.yml that is:
#
#   build:
#     context: ./services
#     dockerfile: ./trade-api/Dockerfile
#
# Two stages. The build stage carries a JDK, Maven, the whole dependency tree and the source: roughly
# 700 MB, none of which is needed to run anything. The runtime stage carries a JRE and one jar. The
# reason to care is not disk: it is that every tool in an image is a tool an attacker has, and a
# compiler in production is a compiler in production.

# ---------- build ----------
FROM maven:3.9-eclipse-temurin-21 AS build

WORKDIR /build

# POMs first, on their own layer. Dependencies change far less often than source, so this layer is
# reused across every rebuild that only touched code.
COPY trading-engine/pom.xml trading-engine/pom.xml
COPY trade-api/pom.xml trade-api/pom.xml
RUN mvn -B -f trading-engine/pom.xml dependency:go-offline \
 && mvn -B -f trade-api/pom.xml dependency:go-offline || true

COPY trading-engine/src trading-engine/src
COPY trade-api/src trade-api/src

# The domain module has to reach the local repository before the service can resolve it. There is no
# aggregator POM: the two projects are separate deliverables from separate sprints.
RUN mvn -B -f trading-engine/pom.xml -DskipTests install \
 && mvn -B -f trade-api/pom.xml -DskipTests package

# ---------- runtime ----------
FROM eclipse-temurin:21-jre-alpine AS runtime

# Not root. A container process that does not need to write to the image should not be able to.
RUN addgroup -S trading && adduser -S -G trading trading

WORKDIR /app
COPY --from=build /build/trade-api/target/trade-api-1.0.0.jar app.jar
USER trading

EXPOSE 8080

# MaxRAMPercentage rather than a fixed -Xmx. The JVM then sizes the heap from the container limit,
# so raising the limit in compose is enough and there is no second number to keep in step.
ENV JAVA_OPTS="-XX:MaxRAMPercentage=75.0 -XX:+ExitOnOutOfMemoryError"

# Unauthenticated on purpose: a health check has no way to obtain a token. It exposes no data.
HEALTHCHECK --interval=15s --timeout=3s --start-period=40s --retries=5 \
  CMD wget -qO- http://localhost:8080/actuator/health | grep -q '"status":"UP"' || exit 1

ENTRYPOINT ["sh", "-c", "exec java $JAVA_OPTS -jar /app/app.jar"]
