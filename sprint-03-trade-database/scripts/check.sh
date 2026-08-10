#!/usr/bin/env bash
#
# Sprint 3 acceptance harness.
#
#   check.sh              run every check
#   check.sh --keep       leave the scratch database in place even on success
#
# The harness creates an empty scratch database inside the running Postgres
# container, runs the apply command you declared in manifest.env against it,
# and asserts behaviour against the names you declared there too. Your working
# database is not touched. The scratch database is dropped when everything
# passes, and left in place when something fails so that you can look at it.
#
# Passing these checks is necessary and not sufficient. Third normal form, the
# quality of an index justification, your historical trade data design and your
# ability to walk the model are assessed in the design review.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPRINT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${SPRINT_DIR}/.." && pwd)"

MIGRATIONS_DIR="${SPRINT_DIR}/migrations"
SEED_DIR="${SPRINT_DIR}/seed"
DESIGN_DIR="${SPRINT_DIR}/design"
PROBE_DIR="${SPRINT_DIR}/probes"
MANIFEST="${SPRINT_DIR}/manifest.env"
HISTORY_DESIGN="${SPRINT_DIR}/DESIGN.md"

SEED_FILES="customer-accounts.csv instrument-reference.csv order-history.csv current-holdings.csv"

KEEP_SCRATCH=0
while [ "$#" -gt 0 ]; do
    case "$1" in
        --keep) KEEP_SCRATCH=1; shift ;;
        -h|--help) sed -n '2,18p' "${BASH_SOURCE[0]}" | sed 's/^#\{1,2\} \{0,1\}//'; exit 0 ;;
        *) printf 'Unknown option: %s\n' "$1" >&2; exit 2 ;;
    esac
done

PASSED=0
FAILED=0

section() { printf '\n%s\n' "$1"; }

pass() {
    printf '  PASS  %s\n' "$1"
    PASSED=$((PASSED + 1))
}

fail() {
    printf '  FAIL  %s\n' "$1"
    shift
    while [ "$#" -gt 0 ]; do
        printf '        %s\n' "$1"
        shift
    done
    FAILED=$((FAILED + 1))
}

abort() {
    printf '\nSTOPPED: %s\n' "$1" >&2
    shift
    while [ "$#" -gt 0 ]; do
        printf '  %s\n' "$1" >&2
        shift
    done
    printf '\nNothing else could be checked until that is fixed.\n' >&2
    exit 1
}

# --- environment -------------------------------------------------------------

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
WORKING_DB="$(read_env POSTGRES_DB trading)"
CHECK_DB="${CHECK_DATABASE:-${WORKING_DB}_check}"

COMPOSE_FILE="${REPO_ROOT}/docker-compose.yml"

dc() {
    docker compose --project-directory "${REPO_ROOT}" -f "${COMPOSE_FILE}" "$@"
}

# One value out of one query against the scratch database. Prints nothing when
# the query returns no rows or fails.
scalar() {
    dc exec -T postgres psql -X -A -t -q -v ON_ERROR_STOP=1 \
        -U "${PG_USER}" -d "${CHECK_DB}" -c "$1" 2>/dev/null | tr -d '\r' | head -n 1 || true
}

drop_scratch() {
    printf 'DROP DATABASE IF EXISTS "%s" WITH (FORCE);\n' "${CHECK_DB}" \
        | dc exec -T postgres psql -X -q -v ON_ERROR_STOP=1 -U "${PG_USER}" -d postgres \
        >/dev/null 2>&1 || true
}

create_scratch() {
    printf 'DROP DATABASE IF EXISTS "%s" WITH (FORCE);\nCREATE DATABASE "%s";\n' \
        "${CHECK_DB}" "${CHECK_DB}" \
        | dc exec -T postgres psql -X -q -v ON_ERROR_STOP=1 -U "${PG_USER}" -d postgres \
        >/dev/null 2>&1
}

# Data rows in a CSV file, header excluded.
csv_rows() {
    file="$1"
    [ -f "${file}" ] || { printf '0'; return; }
    lines="$(grep -c . "${file}" || true)"
    lines="${lines:-0}"
    if [ "${lines}" -gt 0 ]; then
        printf '%s' "$((lines - 1))"
    else
        printf '0'
    fi
}

printf 'Sprint 3 acceptance harness\n'
printf 'Scratch database: %s (inside the postgres container)\n' "${CHECK_DB}"

# --- the manifest ------------------------------------------------------------

section 'Manifest'

[ -f "${MANIFEST}" ] || abort \
    "No manifest.env in ${SPRINT_DIR}." \
    "The harness reads your apply command and your table and column names from" \
    "that file. If you have deleted it, restore it from the repository."

SCHEMA_NAME=""
APPLY_COMMAND=""
ACCOUNTS_TABLE=""
ACCOUNTS_STATUS_COLUMN=""
ACCOUNTS_STATUS_ACTIVE=""
ACCOUNTS_STATUS_SUSPENDED=""
ACCOUNTS_STATUS_CLOSED=""
ORDERS_TABLE=""
ORDERS_IDEMPOTENCY_COLUMN=""

# shellcheck source=/dev/null
. "${MANIFEST}"

SCHEMA_NAME="${SCHEMA_NAME:-public}"

MANIFEST_KEYS="SCHEMA_NAME APPLY_COMMAND ACCOUNTS_TABLE ACCOUNTS_STATUS_COLUMN
ACCOUNTS_STATUS_ACTIVE ACCOUNTS_STATUS_SUSPENDED ACCOUNTS_STATUS_CLOSED
ORDERS_TABLE ORDERS_IDEMPOTENCY_COLUMN"

OUTSTANDING=""
for key in ${MANIFEST_KEYS}; do
    eval "value=\${${key}}"
    if [ -z "${value}" ] || [ "${value}" = "CHANGE_ME" ]; then
        OUTSTANDING="${OUTSTANDING} ${key}"
    fi
done

if [ -n "${OUTSTANDING}" ]; then
    abort "manifest.env is not filled in." \
        "Still set to CHANGE_ME or empty:${OUTSTANDING}" \
        "Declare the names your own schema uses, exactly as they appear in the" \
        "catalogue, and the command that applies your migrations and loads the" \
        "seed data. Postgres folds unquoted identifiers to lower case." \
        "  docker compose exec postgres psql -U ${PG_USER} -d ${WORKING_DB} -c '\\dt'"
fi

valid_identifier() {
    case "$1" in
        ''|*[!A-Za-z0-9_]*) return 1 ;;
        [0-9]*) return 1 ;;
    esac
    return 0
}

for key in SCHEMA_NAME ACCOUNTS_TABLE ACCOUNTS_STATUS_COLUMN ORDERS_TABLE ORDERS_IDEMPOTENCY_COLUMN; do
    eval "value=\${${key}}"
    valid_identifier "${value}" || abort \
        "${key} in manifest.env is not a plain identifier: ${value}" \
        "The harness supports names made of letters, digits and underscores." \
        "Rename the object in a migration rather than quoting an awkward name."
done

for key in ACCOUNTS_STATUS_ACTIVE ACCOUNTS_STATUS_SUSPENDED ACCOUNTS_STATUS_CLOSED; do
    eval "value=\${${key}}"
    case "${value}" in
        *[\'\\]*) abort "${key} in manifest.env contains a quote or a backslash: ${value}" \
                      "Account state values are plain text. Fix the manifest." ;;
    esac
done

pass "manifest.env declares every name the harness needs"

# --- files on disk -----------------------------------------------------------

section 'Deliverables on disk'

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
    abort "No migration files in migrations/." \
        "The schema has to be version controlled as numbered .sql files, applied" \
        "in filename order. Create the directory, put your DDL in" \
        "migrations/001_create_core_tables.sql, and apply it from there." \
        "Nothing typed into a psql session by hand counts."
fi
pass "migrations/ holds ${#MIGRATIONS[@]} SQL file(s)"

BADLY_NAMED=""
for file in "${MIGRATIONS[@]}"; do
    name="$(basename "${file}")"
    case "${name}" in
        [0-9][0-9][0-9]_*.sql) ;;
        *) BADLY_NAMED="${BADLY_NAMED} ${name}" ;;
    esac
done
if [ -n "${BADLY_NAMED}" ]; then
    fail "Migration files that do not follow the numbering convention:${BADLY_NAMED}" \
        "Name every migration NNN_description.sql, starting at 001_. The number" \
        "fixes the order in which the files apply, and the order is the schema."
else
    pass "every migration is named NNN_description.sql"
fi

MISSING_SEED=""
for name in ${SEED_FILES}; do
    [ -s "${SEED_DIR}/${name}" ] || MISSING_SEED="${MISSING_SEED} ${name}"
done
if [ -n "${MISSING_SEED}" ]; then
    abort "Provided seed files missing or empty in seed/:${MISSING_SEED}" \
        "Those four files are the fixture set for the rest of the programme and" \
        "half the checks below need them loaded. Restore them from the" \
        "repository rather than reconstructing them by hand."
fi
pass "seed/ holds the four provided data files"

DIAGRAM=""
for candidate in "${DESIGN_DIR}"/er-diagram.*; do
    if [ -f "${candidate}" ]; then
        DIAGRAM="${candidate}"
        break
    fi
done
if [ -n "${DIAGRAM}" ]; then
    pass "ER diagram committed at design/$(basename "${DIAGRAM}")"
else
    fail "No ER diagram in design/." \
        "Commit design/er-diagram.md holding a Mermaid erDiagram block, or an" \
        "exported design/er-diagram.png or .svg. Every member of the team walks" \
        "it unaided in the review, so it has to be in the repository rather than" \
        "in a document your instructor cannot open."
fi

if [ -s "${DESIGN_DIR}/indexes.md" ]; then
    pass "index justifications committed at design/indexes.md"
else
    fail "No design/indexes.md, or the file is empty." \
        "Three indexes have to be justified against the named queries in the" \
        "sprint brief. A justification names the query, says what the plan does" \
        "with and without the index, and says what the index costs on write."
fi

if [ -s "${HISTORY_DESIGN}" ]; then
    pass "historical trade data design committed at DESIGN.md"
else
    fail "No DESIGN.md in this folder, or the file is empty." \
        "The historical trade data deliverable this sprint is the design, not the" \
        "DDL: what you would store, at what grain, how it is populated, how it is" \
        "queried, and how it is partitioned or archived as it grows. It is" \
        "discussed at the design review."
fi

probe_is_written() {
    [ -f "$1" ] || return 1
    body="$(sed -e 's/--.*$//' "$1" | tr -d '[:space:]')"
    [ -n "${body}" ]
}

for probe in duplicate-idempotency-key orphan-foreign-key; do
    if probe_is_written "${PROBE_DIR}/${probe}.sql"; then
        pass "probes/${probe}.sql has SQL in it"
    else
        fail "probes/${probe}.sql holds no SQL, only the instructions." \
            "Write the statements described in the comments at the top of that" \
            "file. The harness cannot construct an insert against your tables" \
            "without knowing which columns they require."
    fi
done

# --- building the scratch database -------------------------------------------

section "Applying your schema and the seed data into ${CHECK_DB}"

command -v docker >/dev/null 2>&1 || abort \
    "Docker is not on your PATH." \
    "Install Docker Desktop and start it, then try again."

if ! dc exec -T postgres pg_isready -U "${PG_USER}" >/dev/null 2>&1; then
    abort "Cannot reach Postgres in the compose stack." \
        "Start the infrastructure from the repository root:" \
        "  docker compose up -d" \
        "Then check it is healthy:" \
        "  docker compose ps"
fi

create_scratch || abort \
    "Could not create the scratch database ${CHECK_DB}." \
    "Something is holding a connection that will not close, or the user" \
    "${PG_USER} cannot create databases."

APPLY_LOG="$(mktemp)"
trap 'rm -f "${APPLY_LOG}"' EXIT

if ( cd "${SPRINT_DIR}" && TARGET_DATABASE="${CHECK_DB}" bash -c "${APPLY_COMMAND}" ) \
        >"${APPLY_LOG}" 2>&1; then
    pass "your apply command takes an empty database to migrated and seeded"
else
    printf '\n'
    sed 's/^/  | /' "${APPLY_LOG}"
    abort "The apply command failed against an empty database." \
        "Command run, from ${SPRINT_DIR}, with TARGET_DATABASE=${CHECK_DB}:" \
        "  ${APPLY_COMMAND}" \
        "The output above is from that run. An empty database is the state a" \
        "teammate cloning the repository starts from, so this failure is a real" \
        "one rather than an artefact of the harness." \
        "Check that the command is executable, that it reads TARGET_DATABASE," \
        "that it applies migrations in filename order, and that it stops on the" \
        "first error rather than carrying on past it." \
        "The scratch database ${CHECK_DB} has been left in place:" \
        "  docker compose exec postgres psql -U ${PG_USER} -d ${CHECK_DB}"
fi

TABLE_COUNT="$(scalar "SELECT count(*) FROM pg_tables WHERE schemaname = '${SCHEMA_NAME}'")"
if [ "${TABLE_COUNT:-0}" -eq 0 ]; then
    abort "Your apply command exited zero and created nothing in ${CHECK_DB}." \
        "Schema ${SCHEMA_NAME} holds no tables after the command ran. A command" \
        "that reports success without applying anything is worse than one that" \
        "fails, because it passes in your hands and produces an empty database" \
        "on somebody else's machine." \
        "Check that it applies every file in migrations/, that psql runs with" \
        "-v ON_ERROR_STOP=1, and that it targets TARGET_DATABASE rather than" \
        "whichever database it connected to by default."
fi

# --- the schema itself -------------------------------------------------------

section 'Schema'

resolve_relation() {
    scalar "SELECT c.relname FROM pg_class c WHERE c.oid = to_regclass('${SCHEMA_NAME}.$1')"
}

ACCOUNTS_REL="$(resolve_relation "${ACCOUNTS_TABLE}")"
ORDERS_REL="$(resolve_relation "${ORDERS_TABLE}")"

if [ -z "${ACCOUNTS_REL}" ] || [ -z "${ORDERS_REL}" ]; then
    MISSING=""
    [ -n "${ACCOUNTS_REL}" ] || MISSING="${MISSING} ${SCHEMA_NAME}.${ACCOUNTS_TABLE}"
    [ -n "${ORDERS_REL}" ] || MISSING="${MISSING} ${SCHEMA_NAME}.${ORDERS_TABLE}"
    EXISTING="$(scalar "SELECT string_agg(tablename, ', ' ORDER BY tablename) FROM pg_tables WHERE schemaname = '${SCHEMA_NAME}'")"
    abort "Tables named in manifest.env do not exist after the migrations ran:${MISSING}" \
        "Tables that do exist: ${EXISTING:-none}" \
        "Either the manifest names are wrong or the migration that creates those" \
        "tables is missing."
fi
pass "the tables named in manifest.env exist"

column_exists() {
    scalar "SELECT 1 FROM pg_attribute a
            WHERE a.attrelid = to_regclass('${SCHEMA_NAME}.$1')
              AND a.attname = '$2' AND a.attnum > 0 AND NOT a.attisdropped"
}

for pair in "${ACCOUNTS_TABLE}:${ACCOUNTS_STATUS_COLUMN}" "${ORDERS_TABLE}:${ORDERS_IDEMPOTENCY_COLUMN}"; do
    table="${pair%%:*}"
    column="${pair##*:}"
    if [ "$(column_exists "${table}" "${column}")" = "1" ]; then
        pass "${table}.${column} exists"
    else
        columns="$(scalar "SELECT string_agg(a.attname, ', ' ORDER BY a.attnum) FROM pg_attribute a
                           WHERE a.attrelid = to_regclass('${SCHEMA_NAME}.${table}')
                             AND a.attnum > 0 AND NOT a.attisdropped")"
        fail "${table} has no column named ${column}." \
            "Columns on ${table}: ${columns:-none}" \
            "Correct manifest.env, or add the column in a new migration."
    fi
done

UNIQUE_ON_KEY="$(scalar "
    SELECT string_agg(ci.relname, ', ')
    FROM pg_index i
    JOIN pg_class ci ON ci.oid = i.indexrelid
    WHERE i.indrelid = to_regclass('${SCHEMA_NAME}.${ORDERS_TABLE}')
      AND i.indisunique
      AND EXISTS (
          SELECT 1 FROM pg_attribute a
          WHERE a.attrelid = i.indrelid
            AND a.attnum = ANY (string_to_array(i.indkey::text, ' ')::smallint[])
            AND a.attname = '${ORDERS_IDEMPOTENCY_COLUMN}')")"

if [ -n "${UNIQUE_ON_KEY}" ]; then
    pass "a unique constraint covers ${ORDERS_TABLE}.${ORDERS_IDEMPOTENCY_COLUMN} (${UNIQUE_ON_KEY})"
else
    fail "Nothing enforces uniqueness on ${ORDERS_TABLE}.${ORDERS_IDEMPOTENCY_COLUMN}." \
        "Without it, a retried request places a second order. Checking for the" \
        "key in application code before inserting does not close the gap: two" \
        "concurrent requests both find nothing and both insert." \
        "Add the constraint in a new migration."
fi

FK_COUNT="$(scalar "SELECT count(*) FROM pg_constraint c
                    JOIN pg_namespace n ON n.oid = c.connamespace
                    WHERE c.contype = 'f' AND n.nspname = '${SCHEMA_NAME}'")"
FK_COUNT="${FK_COUNT:-0}"
if [ "${FK_COUNT}" -ge 2 ]; then
    pass "${FK_COUNT} foreign key constraint(s) declared"
else
    fail "Only ${FK_COUNT} foreign key constraint(s) in schema ${SCHEMA_NAME}." \
        "The domain has four related entities. An order belongs to an account" \
        "and names an instrument, and a holding belongs to both. Relationships" \
        "that exist only in application code are not relationships."
fi

CHECK_COUNT="$(scalar "SELECT count(*) FROM pg_constraint c
                       JOIN pg_namespace n ON n.oid = c.connamespace
                       WHERE c.contype = 'c' AND n.nspname = '${SCHEMA_NAME}'")"
CHECK_COUNT="${CHECK_COUNT:-0}"
if [ "${CHECK_COUNT}" -ge 3 ]; then
    pass "${CHECK_COUNT} check constraint(s) declared"
else
    fail "Only ${CHECK_COUNT} check constraint(s) in schema ${SCHEMA_NAME}." \
        "The domain states several rules a row cannot break: a quantity is" \
        "positive, a price is positive, a holding is not negative, a state" \
        "column holds one of a fixed set of values. Put them in the schema."
fi

STATUS_CHECK="$(scalar "
    SELECT count(*) FROM pg_constraint c
    WHERE c.contype = 'c'
      AND c.conrelid = to_regclass('${SCHEMA_NAME}.${ACCOUNTS_TABLE}')
      AND pg_get_constraintdef(c.oid) ~ '\\m${ACCOUNTS_STATUS_COLUMN}\\M'")"
if [ "${STATUS_CHECK:-0}" -ge 1 ]; then
    pass "a check constraint restricts ${ACCOUNTS_TABLE}.${ACCOUNTS_STATUS_COLUMN}"
else
    fail "No check constraint covers ${ACCOUNTS_TABLE}.${ACCOUNTS_STATUS_COLUMN}." \
        "An account is active, suspended or closed. Nothing else. A typo in a" \
        "service should be rejected by the database, not stored and discovered" \
        "by a report six weeks later." \
        "A native enumeration type instead of a check constraint does not pass" \
        "this check: declare the permitted values as a constraint."
fi

INDEX_LIST="$(scalar "
    SELECT string_agg(ci.relname, ', ' ORDER BY ci.relname)
    FROM pg_index i
    JOIN pg_class ci ON ci.oid = i.indexrelid
    JOIN pg_class t ON t.oid = i.indrelid
    JOIN pg_namespace n ON n.oid = t.relnamespace
    WHERE n.nspname = '${SCHEMA_NAME}'
      AND NOT i.indisprimary
      AND NOT EXISTS (SELECT 1 FROM pg_constraint k WHERE k.conindid = i.indexrelid)")"

INDEX_COUNT=0
if [ -n "${INDEX_LIST}" ]; then
    INDEX_COUNT="$(printf '%s' "${INDEX_LIST}" | tr ',' '\n' | grep -c . || true)"
fi

if [ "${INDEX_COUNT}" -ge 3 ]; then
    pass "${INDEX_COUNT} index(es) beyond keys and constraints: ${INDEX_LIST}"
else
    fail "Only ${INDEX_COUNT} index(es) beyond primary keys and constraint indexes." \
        "Indexes that Postgres created for you to enforce a primary key or a" \
        "unique constraint are not counted here, because they were not a" \
        "decision. At least three deliberate indexes are required, each one" \
        "justified against a named query in the sprint brief." \
        "Found: ${INDEX_LIST:-none}"
fi

# --- seed data ---------------------------------------------------------------

section 'Seed data'

MISSING_STATES=""
for state in "${ACCOUNTS_STATUS_ACTIVE}" "${ACCOUNTS_STATUS_SUSPENDED}" "${ACCOUNTS_STATUS_CLOSED}"; do
    count="$(scalar "SELECT count(*) FROM \"${SCHEMA_NAME}\".\"${ACCOUNTS_REL}\"
                     WHERE \"${ACCOUNTS_STATUS_COLUMN}\"::text = '${state}'")"
    if [ "${count:-0}" -ge 1 ]; then
        pass "${count} loaded account(s) in state ${state}"
    else
        MISSING_STATES="${MISSING_STATES} ${state}"
    fi
done

if [ -n "${MISSING_STATES}" ]; then
    present="$(scalar "SELECT string_agg(DISTINCT \"${ACCOUNTS_STATUS_COLUMN}\"::text, ', ')
                       FROM \"${SCHEMA_NAME}\".\"${ACCOUNTS_REL}\"")"
    fail "No account in state(s):${MISSING_STATES}" \
        "States present after loading: ${present:-none}" \
        "seed/customer-accounts.csv carries all three. The refusal paths for a" \
        "frozen account and a finished account cannot be tested in Sprint 6" \
        "against data that has neither, so a loader that drops rows it did not" \
        "expect costs you those tests." \
        "If your schema stores different literals, declare them in manifest.env."
fi

EXPECTED_ACCOUNTS="$(csv_rows "${SEED_DIR}/customer-accounts.csv")"
ACCOUNT_COUNT="$(scalar "SELECT count(*) FROM \"${SCHEMA_NAME}\".\"${ACCOUNTS_REL}\"")"
ACCOUNT_COUNT="${ACCOUNT_COUNT:-0}"
if [ "${ACCOUNT_COUNT}" -ge "${EXPECTED_ACCOUNTS}" ]; then
    pass "${ACCOUNT_COUNT} account(s) loaded, from ${EXPECTED_ACCOUNTS} row(s) of provided data"
else
    fail "Only ${ACCOUNT_COUNT} account(s) loaded from ${EXPECTED_ACCOUNTS} row(s) in seed/customer-accounts.csv." \
        "Every row in the provided data belongs in the database. A loader that" \
        "silently skips rows it cannot map hides the mapping problem rather than" \
        "reporting it."
fi

EXPECTED_ORDERS="$(csv_rows "${SEED_DIR}/order-history.csv")"
ORDER_COUNT="$(scalar "SELECT count(*) FROM \"${SCHEMA_NAME}\".\"${ORDERS_REL}\"")"
ORDER_COUNT="${ORDER_COUNT:-0}"
if [ "${ORDER_COUNT}" -ge "${EXPECTED_ORDERS}" ]; then
    pass "${ORDER_COUNT} order(s) loaded, from ${EXPECTED_ORDERS} row(s) of provided data"
else
    fail "Only ${ORDER_COUNT} order(s) loaded from ${EXPECTED_ORDERS} row(s) in seed/order-history.csv." \
        "The file holds orders in four lifecycle states, including rejections." \
        "Sprint 4 analyses them and Sprint 6 tests against them, so a partial" \
        "load costs both."
fi

# --- behaviour ---------------------------------------------------------------

section 'Constraints under load'

run_probe() {
    probe_file="$1"
    expected="$2"
    label="$3"

    if ! probe_is_written "${probe_file}"; then
        printf '  SKIP  %s: probes/%s holds no SQL, reported above.\n' \
            "${label}" "$(basename "${probe_file}")"
        return
    fi

    output="$( { printf '\\set VERBOSITY verbose\nBEGIN;\n'
                 cat "${probe_file}"
                 printf '\nROLLBACK;\n'; } \
        | dc exec -T postgres psql -X -q -v ON_ERROR_STOP=1 \
              -U "${PG_USER}" -d "${CHECK_DB}" 2>&1 )" && status=0 || status=$?

    if [ "${status}" -eq 0 ]; then
        fail "${label}: the database accepted the statement." \
            "The probe ran to completion. Expected SQLSTATE ${expected}, meaning" \
            "the database refused it. Either the constraint is missing, or the" \
            "probe does not do what its comments describe."
        return
    fi

    actual="$(printf '%s\n' "${output}" | sed -n 's/.*ERROR:[[:space:]]*\([0-9A-Z][0-9A-Z][0-9A-Z][0-9A-Z][0-9A-Z]\):.*/\1/p' | head -n 1)"

    if [ "${actual}" = "${expected}" ]; then
        pass "${label}: rejected with SQLSTATE ${expected}"
    else
        fail "${label}: expected SQLSTATE ${expected}, got ${actual:-no SQLSTATE}." \
            "Postgres said:" \
            "$(printf '%s\n' "${output}" | grep -m 1 'ERROR:' || printf '%s' 'no ERROR line in the output')" \
            "A different code usually means the probe itself is wrong rather than" \
            "the schema. 23502 is a missing required column, 23503 a parent row" \
            "that is not there, 42703 a column name that does not exist, 42P01 a" \
            "table name that does not exist."
    fi
}

run_probe "${PROBE_DIR}/duplicate-idempotency-key.sql" 23505 "Duplicate idempotency key"
run_probe "${PROBE_DIR}/orphan-foreign-key.sql" 23503 "Orphan foreign key"

# --- result ------------------------------------------------------------------

printf '\n%s\n' '----------------------------------------------------------------'
printf '%s passed, %s failed\n' "${PASSED}" "${FAILED}"

if [ "${FAILED}" -eq 0 ]; then
    if [ "${KEEP_SCRATCH}" -eq 1 ]; then
        printf 'Scratch database %s kept, as asked.\n' "${CHECK_DB}"
    else
        drop_scratch
        printf 'Scratch database %s dropped.\n' "${CHECK_DB}"
    fi
    printf '\nThe harness is satisfied. It has not read your ER diagram, judged a\n'
    printf 'normal form, or decided whether an index earns its cost on write.\n'
    printf 'That happens in the design review.\n'
    exit 0
fi

printf 'Scratch database %s left in place so you can inspect it:\n' "${CHECK_DB}"
printf '  docker compose exec postgres psql -U %s -d %s\n' "${PG_USER}" "${CHECK_DB}"
exit 1
