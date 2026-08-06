#!/usr/bin/env bash
#
# Creates the platform's Kafka topics per docs/contracts/kafka-topics.md.
#
# Idempotent: uses --if-not-exists, so running it against a broker that
# already has the topics does nothing and exits cleanly. Safe to run on
# every compose start rather than only once.
#
# Runs inside a Kafka broker or client image, so it needs kafka-topics.sh
# on the path. Docker Compose wires this in as the kafka-init service,
# which mounts this file and runs it once the broker reports healthy. Run
# it by hand with:
#
#   docker compose exec kafka bash /kafka-scripts/create-topics.sh
#
# or, if the kafka-init service already ran and exited, rerun it directly:
#
#   docker compose run --rm kafka-init
#
set -euo pipefail

BOOTSTRAP_SERVER="${KAFKA_BOOTSTRAP_SERVERS:-kafka:29092}"
KAFKA_BIN="${KAFKA_BIN:-/opt/kafka/bin}"
TOPICS_SH="${KAFKA_BIN}/kafka-topics.sh"

echo "Waiting for the broker at ${BOOTSTRAP_SERVER}."
until "${TOPICS_SH}" --bootstrap-server "${BOOTSTRAP_SERVER}" --list >/dev/null 2>&1; do
  sleep 2
done
echo "Broker is reachable. Creating topics."

create_topic() {
  local topic="$1"
  local partitions="$2"
  local retention_ms="$3"

  echo "Creating topic '${topic}' (${partitions} partitions, retention ${retention_ms}ms)."
  "${TOPICS_SH}" --bootstrap-server "${BOOTSTRAP_SERVER}" --create --if-not-exists \
    --topic "${topic}" \
    --partitions "${partitions}" \
    --replication-factor 1 \
    --config "retention.ms=${retention_ms}" \
    --config "cleanup.policy=delete"
}

# Primary topics, per the catalogue in docs/contracts/kafka-topics.md.
create_topic "orders"       3 604800000    # 7 days
create_topic "trade-events" 3 2592000000   # 30 days
create_topic "market-data"  6 86400000     # 1 day

# Dead-letter topics. The contract names the pattern "<topic>.DLT" without
# specifying partitions or retention for it, because a dead-letter topic
# carries a small fraction of the volume of its source. One partition is
# enough: nothing about a poison message needs partition-level parallelism,
# and a single partition keeps failure investigation to one ordered log.
# Retention matches the source topic, since a dead-lettered message is worth
# keeping for at least as long as its live counterpart would have been.
create_topic "orders.DLT"       1 604800000
create_topic "trade-events.DLT" 1 2592000000
create_topic "market-data.DLT"  1 86400000

echo "Topic creation complete."
"${TOPICS_SH}" --bootstrap-server "${BOOTSTRAP_SERVER}" --list
