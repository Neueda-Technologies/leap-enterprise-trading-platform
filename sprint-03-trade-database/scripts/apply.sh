#!/usr/bin/env bash
#
# Apply the Sprint 3 migrations, then the seed data, to a Postgres database in
# the compose stack.
#
#   apply.sh                       migrations then seed, against $POSTGRES_DB
#   apply.sh --fresh               drop and recreate the database first
#   apply.sh --no-seed             migrations only
#   apply.sh --database NAME       target a different database in the same
#                                  container, which is how check.sh builds its
#                                  scratch database
#
# Files are applied in filename order. Any error stops the run: psql is invoked
# with ON_ERROR_STOP so a half-applied migration cannot pass unnoticed.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPRINT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${SPRINT_DIR}/.." && pwd)"

MIGRATIONS_DIR="${SPRINT_DIR}/migrations"
SEED_DIR="${SPRINT_DIR}/seed"

fail() {
    printf '\nFAILED: %s\n' "$1" >&2
    shift
    while [ "$#" -gt 0 ]; do
        printf '  %s\n' "$1" >&2
        shift
    done
    exit 1
}

usage() {
    sed -n '2,16p' "${BASH_SOURCE[0]}" | sed 's/^#\{1,2\} \{0,1\}//'
}

# --- arguments ---------------------------------------------------------------

DATABASE=""
FRESH=0
WITH_SEED=1

while [ "$#" -gt 0 ]; do
    case "$1" in
        --fresh)    FRESH=1; shift ;;
        --no-seed)  WITH_SEED=0; shift ;;
        --database)
            [ "$#" -ge 2 ] || fail "--database needs a database name."
            DATABASE="$2"; shift 2 ;;
        -h|--help)  usage; exit 0 ;;
        *)          fail "Unknown option: $1" "Run apply.sh --help for the options." ;;
    esac
done

# --- environment -------------------------------------------------------------

# Read one key out of the repository .env, falling back to the documented
# default. Values are taken literally, minus surrounding quotes.
read_env() {
    key="$1"
    fallback="$2"
    value=""
    if [ -f "${REPO_ROOT}/.env" ]; then
        value="$(sed -n "s/^[[:space:]]*${key}=//p" "${REPO_ROOT}/.env" | tail -n 1 | tr -d '\r')"
        value="${value%\"}"; value="${value#\"}"
        value="${value%\'}"; value="${value#\'}"
    fi
    if [ -z "${value}" ]; then
        value="${fallback}"
    fi
    printf '%s' "${value}"
}

PG_USER="$(read_env POSTGRES_USER postgres)"
DEFAULT_DB="$(read_env POSTGRES_DB trading)"
[ -n "${DATABASE}" ] || DATABASE="${DEFAULT_DB}"

COMPOSE_FILE="${REPO_ROOT}/docker-compose.yml"
[ -f "${COMPOSE_FILE}" ] || fail \
    "No docker-compose.yml at ${COMPOSE_FILE}." \
    "Run this script from inside the repository, without moving the sprint folder."

dc() {
    docker compose --project-directory "${REPO_ROOT}" -f "${COMPOSE_FILE}" "$@"
}

psql_on() {
    # psql_on <database> [extra psql arguments...], SQL on stdin
    db="$1"; shift
    dc exec -T postgres psql -X -q -v ON_ERROR_STOP=1 -U "${PG_USER}" -d "${db}" "$@"
}

# --- preflight ---------------------------------------------------------------

command -v docker >/dev/null 2>&1 || fail \
    "Docker is not on your PATH." \
    "Install Docker Desktop and start it, then try again."

if ! dc exec -T postgres pg_isready -U "${PG_USER}" >/dev/null 2>&1; then
    fail "Cannot reach Postgres in the compose stack." \
        "Start the infrastructure from the repository root:" \
        "  docker compose up -d" \
        "Then check it is healthy:" \
        "  docker compose ps" \
        "If the container is running but not accepting connections, read its logs:" \
        "  docker compose logs postgres"
fi

# --- file discovery ----------------------------------------------------------

# Prints the .sql files directly inside a directory, one per line, in filename
# order. Prints nothing if the directory is missing or holds no SQL.
list_sql() {
    dir="$1"
    [ -d "${dir}" ] || return 0
    find "${dir}" -maxdepth 1 -type f -name '*.sql' -print | LC_ALL=C sort
}

MIGRATIONS=()
while IFS= read -r file; do
    [ -n "${file}" ] || continue
    MIGRATIONS[${#MIGRATIONS[@]}]="${file}"
done < <(list_sql "${MIGRATIONS_DIR}")

if [ "${#MIGRATIONS[@]}" -eq 0 ]; then
    fail "No migration files in ${MIGRATIONS_DIR}." \
        "A migration is a .sql file numbered from 001_, for example" \
        "001_create_core_tables.sql. See migrations/README.md."
fi

SEEDS=()
if [ "${WITH_SEED}" -eq 1 ]; then
    while IFS= read -r file; do
        [ -n "${file}" ] || continue
        SEEDS[${#SEEDS[@]}]="${file}"
    done < <(list_sql "${SEED_DIR}")
    if [ "${#SEEDS[@]}" -eq 0 ]; then
        fail "No seed files in ${SEED_DIR}." \
            "Seed data is part of the deliverable: accounts in all three states," \
            "instruments and orders. See seed/README.md." \
            "To apply migrations on their own, run apply.sh --no-seed."
    fi
fi

# --- apply -------------------------------------------------------------------

if [ "${FRESH}" -eq 1 ]; then
    printf 'Dropping and recreating database %s\n' "${DATABASE}"
    if ! printf 'DROP DATABASE IF EXISTS %s WITH (FORCE);\nCREATE DATABASE %s;\n' \
        "\"${DATABASE}\"" "\"${DATABASE}\"" | psql_on postgres >/dev/null; then
        fail "Could not recreate database ${DATABASE}." \
            "Something is holding a connection that will not close, or the user" \
            "${PG_USER} cannot create databases."
    fi
fi

if ! psql_on "${DATABASE}" -c 'SELECT 1' >/dev/null 2>&1; then
    fail "Database ${DATABASE} does not exist or cannot be opened as ${PG_USER}." \
        "Create it by rerunning with --fresh, or check POSTGRES_DB and" \
        "POSTGRES_USER in your .env against the running container."
fi

printf 'Applying %s migration file(s) to %s\n' "${#MIGRATIONS[@]}" "${DATABASE}"
for file in "${MIGRATIONS[@]}"; do
    printf '  %s\n' "$(basename "${file}")"
    if ! psql_on "${DATABASE}" < "${file}"; then
        fail "Migration $(basename "${file}") did not apply cleanly to ${DATABASE}." \
            "The error from Postgres is above." \
            "If the objects already exist, rebuild from scratch:" \
            "  ${0} --fresh"
    fi
done

if [ "${WITH_SEED}" -eq 1 ]; then
    printf 'Applying %s seed file(s) to %s\n' "${#SEEDS[@]}" "${DATABASE}"
    for file in "${SEEDS[@]}"; do
        printf '  %s\n' "$(basename "${file}")"
        if ! psql_on "${DATABASE}" < "${file}"; then
            fail "Seed file $(basename "${file}") did not apply cleanly to ${DATABASE}." \
                "The error from Postgres is above." \
                "Duplicate key errors mean the data is already loaded; reload with:" \
                "  ${0} --fresh"
        fi
    done
fi

printf '\nDone. %s now holds the schema from migrations/' "${DATABASE}"
if [ "${WITH_SEED}" -eq 1 ]; then
    printf ' and the data from seed/'
fi
printf '.\n'
