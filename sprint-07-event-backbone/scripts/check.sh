#!/usr/bin/env bash
#
# Sprint 7 acceptance harness.
#
#   check.sh              static checks only. No container, no broker, no
#                         database, and no call to Fauxnance.
#   check.sh --live       the static checks, then the probes against your
#                         running stack.
#   check.sh --reuse      reuse the scratch Python environment from the last run
#   check.sh --keep       leave the scratch environment in place after a pass
#
# Static mode builds the executor from a clean state, installs the poller and
# the pipeline into an empty Python environment, runs the tests it finds there,
# runs the characterisation tests you wrote around your Sprint 6 service, reads
# the commit history for the order the two happened in, and scans every file in
# this folder for a Fauxnance key.
#
# Live mode needs the whole stack up: the broker with the three topics, your
# schema and seed data, the auth stub, your Trade REST API, your executor and
# your poller. It asks the broker what the topics look like, places one order
# through your API, watches it settle, replays the order message to see whether
# the account is debited twice, waits for a quote, and runs your pipeline three
# times around a planted bad row.
#
# Both modes read your names from manifest.env, so the harness asserts your
# design rather than dictating one.
#
# Passing these checks is necessary and not sufficient. Whether the transaction
# encloses the work that has to be atomic, whether the fill rule is defensible,
# whether the quota arithmetic holds and whether the characterisation tests pin
# behaviour worth pinning are assessed at the review.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPRINT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

MANIFEST="${SPRINT_DIR}/manifest.env"

MVN_FLAGS=(-B)

# A suite that pins one order placement path is more than two tests.
MIN_CHARACTERISATION_TESTS=3

# The Fauxnance floor. Below this, no configuration of the poller survives even
# a half-day session and the quotes are delayed anyway.
MIN_POLL_INTERVAL=15
DAILY_QUOTA=2000

LIVE=0
KEEP_VENV=0
REUSE_VENV=0
while [ "$#" -gt 0 ]; do
    case "$1" in
        --live) LIVE=1; shift ;;
        --keep) KEEP_VENV=1; shift ;;
        --reuse) REUSE_VENV=1; shift ;;
        -h|--help) sed -n '2,30p' "${BASH_SOURCE[0]}" | sed 's/^#\{1,2\} \{0,1\}//'; exit 0 ;;
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

note() { printf '  NOTE  %s\n' "$1"; }

skip() { printf '  SKIP  %s\n' "$1"; }

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

printf 'Sprint 7 acceptance harness\n'
if [ "${LIVE}" -eq 1 ]; then
    printf 'Static checks, then live probes against your running stack.\n'
else
    printf 'Static checks only. Add --live once the whole stack is up.\n'
fi

# --- the manifest ------------------------------------------------------------

section 'Manifest'

[ -f "${MANIFEST}" ] || abort \
    "No manifest.env in ${SPRINT_DIR}." \
    "The harness reads your package names, your topic names, your consumer" \
    "group and the commands live mode runs from that file. If you have deleted" \
    "it, restore it from the repository."

EXECUTOR_DIR=""
EXECUTOR_BASE_PACKAGE=""
EXECUTOR_CONSUMER_GROUP=""
POLLER_DIR=""
POLLER_PACKAGE_NAME=""
POLL_INTERVAL_SECONDS=""
ETL_DIR=""
SPRINT_SIX_DIR=""
CHARACTERISATION_TEST_DIR=""
ORDERS_TOPIC=""
ORDERS_PARTITIONS=""
TRADE_EVENTS_TOPIC=""
TRADE_EVENTS_PARTITIONS=""
MARKET_DATA_TOPIC=""
MARKET_DATA_PARTITIONS=""
KAFKA_CONTAINER=""
KAFKA_BIN=""
KAFKA_BOOTSTRAP=""
POSTGRES_CONTAINER=""
PG_DATABASE=""
PG_USER=""
SERVICE_HOST=""
SERVICE_PORT=""
AUTH_HOST=""
AUTH_PORT=""
LIVE_PASSWORD=""
LIVE_ACTIVE_USERNAME=""
LIVE_ACTIVE_ACCOUNT_ID=""
LIVE_TRADABLE_SYMBOL=""
LIVE_PROBE_QUANTITY=""
LIVE_PROBE_LIMIT_PRICE=""
EXECUTION_TIMEOUT_SECONDS=""
ETL_RUN_COMMAND=""
ETL_FACT_COUNT_COMMAND=""
ETL_DEAD_LETTER_COUNT_COMMAND=""
ETL_BAD_ROW_INSERT_SQL=""
ETL_BAD_ROW_CLEANUP_SQL=""

# shellcheck source=/dev/null
. "${MANIFEST}"

# The folder names come first, because everything the harness reads it finds
# through one of them. They ship filled in, fixed by the engineering contract.
PATH_KEYS="EXECUTOR_DIR POLLER_DIR ETL_DIR SPRINT_SIX_DIR"

MISSING_PATHS=""
for key in ${PATH_KEYS}; do
    eval "value=\${${key}}"
    if [ -z "${value}" ] || [ "${value}" = "CHANGE_ME" ]; then
        MISSING_PATHS="${MISSING_PATHS} ${key}"
    fi
done

if [ -n "${MISSING_PATHS}" ]; then
    abort "manifest.env does not say where the deliverables are." \
        "Still empty or set to CHANGE_ME:${MISSING_PATHS}" \
        "All four ship filled in, because the engineering contract in" \
        "README.md fixes where the three projects are rooted and where your" \
        "Sprint 6 service lives. Restore them, or correct them to the folders" \
        "you actually used."
fi

pass "manifest.env says where the deliverables are"

EXECUTOR_PATH="${SPRINT_DIR}/${EXECUTOR_DIR}"
POLLER_PATH="${SPRINT_DIR}/${POLLER_DIR}"
ETL_PATH="${SPRINT_DIR}/${ETL_DIR}"
SPRINT_SIX_PATH="${SPRINT_DIR}/${SPRINT_SIX_DIR}"
SPRINT_SIX_SRC="${SPRINT_SIX_PATH}/src/main/java"
EXECUTOR_MAIN_SRC="${EXECUTOR_PATH}/src/main/java"

# --- files on disk -----------------------------------------------------------

section 'Deliverables on disk'

CONTRACT_LINES=(
    "The engineering contract for this sprint is three projects rooted here."
    "One Maven project at ${EXECUTOR_DIR}/ holds the Trade Executor: a consumer in"
    "the group ${EXECUTOR_CONSUMER_GROUP:-trade-executor}, on Java 21 and Maven 3.9 or later, that prices"
    "an order against a live Fauxnance quote, settles order, cash and position"
    "in one transaction, and publishes to ${TRADE_EVENTS_TOPIC:-trade-events}."
    "One Python project at ${POLLER_DIR}/ publishes batched quotes to ${MARKET_DATA_TOPIC:-market-data}"
    "inside the daily quota, and one at ${ETL_DIR}/ performs one incremental"
    "load into FACT_TRADES and its dimensions per"
    "contracts/analytics-schema.sql, with bad rows dead-lettered rather than"
    "dropped. Both install from their own pyproject.toml and declare their"
    "test dependencies under a dev optional dependency group."
    "On day one of the sprint this is the expected result. Start with the"
    "poller: it is the smallest of the three, and a topic with nothing on it"
    "is hard to debug against."
)

[ -f "${EXECUTOR_PATH}/pom.xml" ] || abort \
    "No pom.xml at ${EXECUTOR_DIR}/." \
    "${CONTRACT_LINES[@]}"

[ -f "${POLLER_PATH}/pyproject.toml" ] || abort \
    "No pyproject.toml at ${POLLER_DIR}/." \
    "${CONTRACT_LINES[@]}"

[ -f "${ETL_PATH}/pyproject.toml" ] || abort \
    "No pyproject.toml at ${ETL_DIR}/." \
    "${CONTRACT_LINES[@]}"

[ -d "${SPRINT_SIX_SRC}" ] || abort \
    "Nothing at ${SPRINT_SIX_DIR}/src/main/java." \
    "That is the service this sprint characterises and then changes. If your" \
    "Sprint 6 work is somewhere else, correct SPRINT_SIX_DIR in manifest.env."

pass "the executor build, the two Python projects and your Sprint 6 sources are all present"

# --- the rest of the manifest ------------------------------------------------

section 'Names in the manifest'

STATIC_KEYS="EXECUTOR_BASE_PACKAGE EXECUTOR_CONSUMER_GROUP POLLER_PACKAGE_NAME
POLL_INTERVAL_SECONDS CHARACTERISATION_TEST_DIR ORDERS_TOPIC ORDERS_PARTITIONS
TRADE_EVENTS_TOPIC TRADE_EVENTS_PARTITIONS MARKET_DATA_TOPIC
MARKET_DATA_PARTITIONS"

LIVE_KEYS="KAFKA_BIN KAFKA_BOOTSTRAP PG_DATABASE PG_USER SERVICE_HOST
SERVICE_PORT AUTH_HOST AUTH_PORT LIVE_PASSWORD LIVE_ACTIVE_USERNAME
LIVE_ACTIVE_ACCOUNT_ID LIVE_TRADABLE_SYMBOL LIVE_PROBE_QUANTITY
LIVE_PROBE_LIMIT_PRICE EXECUTION_TIMEOUT_SECONDS ETL_RUN_COMMAND
ETL_FACT_COUNT_COMMAND ETL_DEAD_LETTER_COUNT_COMMAND ETL_BAD_ROW_INSERT_SQL
ETL_BAD_ROW_CLEANUP_SQL"

REQUIRED_KEYS="${STATIC_KEYS}"
[ "${LIVE}" -eq 1 ] && REQUIRED_KEYS="${STATIC_KEYS} ${LIVE_KEYS}"

OUTSTANDING=""
for key in ${REQUIRED_KEYS}; do
    eval "value=\${${key}}"
    if [ -z "${value}" ] || [ "${value}" = "CHANGE_ME" ]; then
        OUTSTANDING="${OUTSTANDING} ${key}"
    fi
done

if [ -n "${OUTSTANDING}" ]; then
    abort "manifest.env is not filled in." \
        "Still empty or set to CHANGE_ME:${OUTSTANDING}" \
        "Each one is a name from your own design, and the comment above it in" \
        "the file says what it is. The keys that ship filled in are fixed by" \
        "contracts/kafka-topics.md, by the compose file or by the auth stub." \
        "The three ETL commands have no defensible default, because the" \
        "analytical store is your choice: worked examples are in the file." \
        "The container names are allowed to be empty, and mean that the" \
        "harness should use the tools on your PATH instead."
fi

printf '%s' "${EXECUTOR_BASE_PACKAGE}" \
    | grep -qE '^[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)*$' || abort \
    "EXECUTOR_BASE_PACKAGE is not a Java package name: ${EXECUTOR_BASE_PACKAGE}" \
    "Write it as it appears in your package declaration, for example" \
    "  EXECUTOR_BASE_PACKAGE=com.tradingplatform.executor"

printf '%s' "${POLLER_PACKAGE_NAME}" \
    | grep -qE '^[A-Za-z_][A-Za-z0-9_]*$' || abort \
    "POLLER_PACKAGE_NAME is not an importable Python package name: ${POLLER_PACKAGE_NAME}" \
    "Give the name a teammate types after import, without a path and without" \
    "a dot."

for key in ORDERS_PARTITIONS TRADE_EVENTS_PARTITIONS MARKET_DATA_PARTITIONS POLL_INTERVAL_SECONDS; do
    eval "value=\${${key}}"
    printf '%s' "${value}" | grep -qE '^[0-9]+$' || abort \
        "${key} in manifest.env is not a whole number: ${value}"
done

pass "manifest.env declares every name this run needs"

CHARACTERISATION_PATH="${SPRINT_DIR}/${CHARACTERISATION_TEST_DIR}"

# --- the toolchain -----------------------------------------------------------

section 'Toolchain'

command -v mvn >/dev/null 2>&1 || abort \
    "mvn is not on your PATH. Install Maven 3.9 or later and try again."

command -v python3 >/dev/null 2>&1 || abort \
    "python3 is not on your PATH. Install Python 3.12 or later and try again."

python3 -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 12) else 1)' || abort \
    "python3 is older than 3.12: $(python3 -c 'import platform; print(platform.python_version())')" \
    "Both Python projects in this sprint require 3.12 or later."

if [ "${LIVE}" -eq 1 ]; then
    command -v curl >/dev/null 2>&1 || abort \
        "curl is not on your PATH, and live mode probes your API with it."
fi

pass "mvn and python3 $(python3 -c 'import platform; print(platform.python_version())') are on the PATH"

# --- secrets -----------------------------------------------------------------

section 'Secrets'

# A Fauxnance key is fnx_, the cohort, an underscore and a long tail. Nothing
# resembling one belongs in a file that is committed.
KEY_PATTERN='fnx_[A-Za-z0-9-]+_[A-Za-z0-9]{16,}'

# The base URL carrying a credential in the query string, which is the other
# way a key reaches a commit.
URL_KEY_PATTERN='execute-api[^[:space:]]*[?&](api[_-]?key|apikey|key)='

# The key assigned as a literal rather than read from the environment, and a
# long literal set as the X-Api-Key header. Both forms require a value long
# enough to be a key, so that a test passing "k" into a settings object is not
# reported as a leak.
LITERAL_PATTERN='(FAUXNANCE[_.-]?API[_.-]?KEY["'"'"']?[[:space:]]*[:=][[:space:]]*["'"'"'][A-Za-z0-9_./+-]{16,}["'"'"'])|([Xx]-[Aa]pi-[Kk]ey["'"'"']?[[:space:]]*[:=][[:space:]]*["'"'"'][A-Za-z0-9_-]{16,}["'"'"'])'

scan_for() {
    grep -rInE "$1" "${SPRINT_DIR}" \
        --exclude-dir=.check-venv --exclude-dir=target --exclude-dir=__pycache__ \
        --exclude-dir=.pytest_cache --exclude-dir=.venv --exclude-dir=node_modules \
        --exclude='*.duckdb' 2>/dev/null | sed "s|^${SPRINT_DIR}/||" || true
}

LEAKS=()
for pattern in "${KEY_PATTERN}" "${URL_KEY_PATTERN}" "${LITERAL_PATTERN}"; do
    while IFS= read -r hit; do
        [ -n "${hit}" ] || continue
        LEAKS[${#LEAKS[@]}]="${hit}"
    done <<EOF
$(scan_for "${pattern}")
EOF
done

if [ "${#LEAKS[@]}" -eq 0 ]; then
    pass "no Fauxnance key literal anywhere under ${SPRINT_DIR##*/}"
else
    fail "Something that looks like a Fauxnance key is in a committed file." \
        ${LEAKS[@]+"${LEAKS[@]}"} \
        "Two services in this sprint call Fauxnance and both read the key from" \
        "FAUXNANCE_API_KEY. Revoke the key with your instructor, then remove" \
        "it. Deleting the line does not remove it from the history, so tell" \
        "your instructor either way."
fi

# --- the executor build ------------------------------------------------------

section 'Building the executor'

BUILD_LOG="$(mktemp)"
WORK_LOG="$(mktemp)"
RESP_BODY="$(mktemp)"
CONSUMED="$(mktemp)"
OFF_BEFORE="$(mktemp)"
OFF_AFTER="$(mktemp)"
trap 'rm -f "${BUILD_LOG}" "${WORK_LOG}" "${RESP_BODY}" "${CONSUMED}" "${OFF_BEFORE}" "${OFF_AFTER}"' EXIT

if (cd "${EXECUTOR_PATH}" && mvn "${MVN_FLAGS[@]}" clean verify) >"${BUILD_LOG}" 2>&1; then
    pass "mvn clean verify succeeds in ${EXECUTOR_DIR}"
else
    printf '\n'
    tail -n 30 "${BUILD_LOG}" | sed 's/^/  | /'
    fail "The executor does not build from a clean state." \
        "The output above is the tail of the build. Reproduce it with:" \
        "  cd ${EXECUTOR_PATH} && mvn clean verify" \
        "If it cannot resolve your Sprint 5 domain module, that module has to" \
        "reach your local Maven repository first. There is no aggregator" \
        "build:" \
        "  cd ${SPRINT_DIR}/../sprint-05-domain-engine && mvn install"
fi

EXECUTOR_SOURCES="$(find "${EXECUTOR_MAIN_SRC}" -type f -name '*.java' ! -name 'package-info.java' 2>/dev/null | wc -l | tr -d ' ')"

if [ "${EXECUTOR_SOURCES}" -ge 1 ]; then
    pass "${EXECUTOR_DIR} holds ${EXECUTOR_SOURCES} source file(s)"
else
    abort "No Java source under ${EXECUTOR_DIR}/src/main/java." \
        "The listener, the fill rule, the settlement, the quote client and the" \
        "producer are yours to design from the brief and from" \
        "contracts/kafka-topics.md." \
        "On day one of the sprint this is the expected result. Write the" \
        "application class and a listener that logs what it consumed, then" \
        "come back." \
        "A package-info.java does not count towards this number."
fi

EXECUTOR_TESTS="$(find "${EXECUTOR_PATH}/src/test/java" -type f -name '*.java' 2>/dev/null | wc -l | tr -d ' ')"
if [ "${EXECUTOR_TESTS}" -ge 1 ]; then
    pass "${EXECUTOR_DIR}/src/test/java holds ${EXECUTOR_TESTS} source file(s)"
else
    fail "No tests for the executor." \
        "The fill rule, the guarded transition and the event shape are all" \
        "decidable without a broker, a database or a network: the repository" \
        "is mockable and the HTTP layer is fakeable. The three cases worth" \
        "writing first are a delivery that loses the guarded transition and" \
        "moves no money, a quote that could not be obtained, and a lost" \
        "optimistic lock that is retried." \
        "A deliverable with no tests is assessed as one."
fi

# --- the Python projects -----------------------------------------------------

section 'Installing the Python projects into a scratch environment'

VENV_DIR="${CHECK_VENV:-${SPRINT_DIR}/.check-venv}"
VENV_PY="${VENV_DIR}/bin/python"

if [ "${REUSE_VENV}" -eq 1 ] && [ -x "${VENV_PY}" ]; then
    pass "reusing the scratch environment at $(basename "${VENV_DIR}")"
else
    rm -rf "${VENV_DIR}"
    if ! python3 -m venv "${VENV_DIR}" >"${WORK_LOG}" 2>&1; then
        sed 's/^/  | /' "${WORK_LOG}"
        abort "Could not create a virtual environment at ${VENV_DIR}." \
            "On Debian and Ubuntu this usually means python3-venv is not" \
            "installed."
    fi

    if "${VENV_PY}" -m pip install --quiet --disable-pip-version-check \
        -e "${POLLER_PATH}[dev]" -e "${ETL_PATH}[dev]" \
        >"${WORK_LOG}" 2>&1; then
        pass "the poller and the pipeline install into a clean environment"
    else
        printf '\n'
        tail -n 30 "${WORK_LOG}" | sed 's/^/  | /'
        abort "pip could not install one of the two Python projects." \
            "The output above is from installing them into an environment with" \
            "nothing in it, which is the state a teammate cloning the" \
            "repository starts from." \
            "Both projects install as ${POLLER_DIR}[dev] and ${ETL_DIR}[dev]," \
            "so both need a dev optional dependency group carrying pytest." \
            "Reproduce it with:" \
            "  python3 -m venv .check-venv" \
            "  .check-venv/bin/python -m pip install -e '${POLLER_PATH}[dev]'"
    fi
fi

section 'The poller'

POLLER_PACKAGE_PATH="${POLLER_PATH}/src/${POLLER_PACKAGE_NAME}"
if [ ! -d "${POLLER_PACKAGE_PATH}" ]; then
    fail "No package directory at ${POLLER_DIR}/src/${POLLER_PACKAGE_NAME}." \
        "POLLER_PACKAGE_NAME in manifest.env says ${POLLER_PACKAGE_NAME} and" \
        "nothing by that name is under ${POLLER_DIR}/src. Either correct the" \
        "manifest or move the package."
else
    POLLER_STATEMENTS="$(python3 - "${POLLER_PACKAGE_PATH}" <<'PY' 2>/dev/null || true
import ast
import pathlib
import sys

total = 0
for path in sorted(pathlib.Path(sys.argv[1]).rglob("*.py")):
    try:
        tree = ast.parse(path.read_text(encoding="utf-8"))
    except (OSError, SyntaxError):
        continue
    body = list(tree.body)
    if body and isinstance(body[0], ast.Expr) and isinstance(body[0].value, ast.Constant) \
            and isinstance(body[0].value.value, str):
        body = body[1:]
    total += len(body)
print(total)
PY
)"

    if [ "${POLLER_STATEMENTS:-0}" -ge 1 ]; then
        pass "the poller package holds ${POLLER_STATEMENTS} top-level statement(s) of code"
    else
        fail "Every module under ${POLLER_DIR}/src/${POLLER_PACKAGE_NAME} is empty or a docstring and nothing else." \
            "The poller is the smallest of the three deliverables and the one" \
            "to write first, on the grounds that a topic with nothing on it is" \
            "hard to debug against."
    fi
fi

POLLER_TESTS="$(find "${POLLER_PATH}/tests" -type f -name 'test_*.py' 2>/dev/null | wc -l | tr -d ' ')"
if [ "${POLLER_TESTS}" -ge 1 ]; then
    if (cd "${POLLER_PATH}" && "${VENV_PY}" -m pytest -q) >"${WORK_LOG}" 2>&1; then
        pass "the poller's test suite passes"
    else
        printf '\n'
        tail -n 25 "${WORK_LOG}" | sed 's/^/  | /'
        fail "The poller's test suite does not pass." \
            "Reproduce it with:" \
            "  cd ${POLLER_PATH} && ${VENV_PY} -m pytest"
    fi
else
    fail "No tests under ${POLLER_DIR}/tests." \
        "Everything this service decides is testable with the HTTP session and" \
        "the Kafka producer faked: that a batch is split at 25, that one" \
        "message goes out per symbol keyed by symbol, that the envelope" \
        "matches the contract, that a 429 is not retried, and that one bad" \
        "symbol does not stop the cycle." \
        "None of that needs a broker or a request against your quota."
fi

INTERVAL_REPORT="$(awk -v interval="${POLL_INTERVAL_SECONDS}" -v quota="${DAILY_QUOTA}" 'BEGIN {
    per_day = 86400 / interval
    hours = quota / per_day * 24
    printf "%d %.1f", per_day, hours
}')"
POLLS_PER_DAY="${INTERVAL_REPORT%% *}"
QUOTA_HOURS="${INTERVAL_REPORT##* }"

if [ "${POLL_INTERVAL_SECONDS}" -lt "${MIN_POLL_INTERVAL}" ]; then
    fail "POLL_INTERVAL_SECONDS is ${POLL_INTERVAL_SECONDS}, and one batch call per cycle at that rate is ${POLLS_PER_DAY} requests a day." \
        "The quota is ${DAILY_QUOTA} per key per day and it is shared with the" \
        "Trade Executor. At this interval the key lasts ${QUOTA_HOURS} hours" \
        "with nothing left for pricing a fill." \
        "Fauxnance serves delayed quotes, so polling faster than the data" \
        "changes buys requests and nothing else. Enforce a floor in the" \
        "poller's configuration rather than documenting one and hoping."
else
    pass "POLL_INTERVAL_SECONDS is ${POLL_INTERVAL_SECONDS}"
    note "one batch call per cycle at that interval is ${POLLS_PER_DAY} requests"
    note "a day, so a key lasts ${QUOTA_HOURS} hours of continuous running"
    note "before the executor gets nothing. Whether your arithmetic and your"
    note "batching agree with that is the assessed part, and it is asked about"
    note "at the review."
fi

note "the harness cannot read a batch size out of your code without dictating"
note "how you write it. What live mode does instead is watch market-data for"
note "one polling interval and report how many distinct symbols arrived in it:"
note "several symbols inside one cycle is evidence of a batched call, and one"
note "symbol per cycle is evidence of the opposite."

section 'The pipeline'

ETL_TESTS="$(find "${ETL_PATH}" -type f -name 'test_*.py' ! -path '*/.venv/*' 2>/dev/null | wc -l | tr -d ' ')"
if [ "${ETL_TESTS}" -ge 1 ]; then
    if (cd "${ETL_PATH}" && "${VENV_PY}" -m pytest -q) >"${WORK_LOG}" 2>&1; then
        pass "the pipeline's test suite passes"
    else
        printf '\n'
        tail -n 25 "${WORK_LOG}" | sed 's/^/  | /'
        fail "The pipeline's test suite does not pass." \
            "Reproduce it with:" \
            "  cd ${ETL_PATH} && ${VENV_PY} -m pytest"
    fi
else
    note "no test_*.py under ${ETL_DIR}. Not a criterion this sprint, and the"
    note "row-level checks that decide what is dead-lettered are the cheapest"
    note "thing in the pipeline to test without a database."
fi

# --- characterisation tests --------------------------------------------------

section 'Characterisation tests around your Sprint 6 service'

CHARACTERISATION_FILES=()
while IFS= read -r file; do
    [ -n "${file}" ] || continue
    CHARACTERISATION_FILES[${#CHARACTERISATION_FILES[@]}]="${file}"
done < <(find "${CHARACTERISATION_PATH}" -type f -name '*.java' 2>/dev/null | LC_ALL=C sort)

CHARACTERISATION_COUNT=0

if [ "${#CHARACTERISATION_FILES[@]}" -eq 0 ]; then
    fail "No Java sources under ${CHARACTERISATION_TEST_DIR}." \
        "The deliverable is characterisation tests first and the change to" \
        "your Sprint 6 service second. A characterisation test does not assert" \
        "what that service should do. It records what it does now, including" \
        "the parts you disagree with, so that a change which alters behaviour" \
        "by accident fails loudly instead of quietly." \
        "Put them in one package of their own under your Sprint 6 test tree," \
        "and point CHARACTERISATION_TEST_DIR at it."
else
    for file in "${CHARACTERISATION_FILES[@]}"; do
        in_file="$(grep -c -E '^[[:space:]]*@(Test|ParameterizedTest)\b' "${file}" 2>/dev/null || true)"
        CHARACTERISATION_COUNT=$((CHARACTERISATION_COUNT + in_file))
    done

    if [ "${CHARACTERISATION_COUNT}" -ge "${MIN_CHARACTERISATION_TESTS}" ]; then
        pass "${CHARACTERISATION_COUNT} characterisation test(s) across ${#CHARACTERISATION_FILES[@]} file(s)"
    else
        fail "Only ${CHARACTERISATION_COUNT} test(s) under ${CHARACTERISATION_TEST_DIR}, and ${MIN_CHARACTERISATION_TESTS} is the minimum." \
            "Pinning one order placement path takes more than that. What comes" \
            "back for an order the account can afford, which code and status" \
            "come back for a reused idempotency key, and what is written to" \
            "the order row and the cash when an order is accepted are three" \
            "separate observations."
    fi

    TEST_CLASSES=""
    for file in "${CHARACTERISATION_FILES[@]}"; do
        base="$(basename "${file}" .java)"
        TEST_CLASSES="${TEST_CLASSES}${TEST_CLASSES:+,}${base}"
    done

    if (cd "${SPRINT_SIX_PATH}" && mvn "${MVN_FLAGS[@]}" test \
            "-Dtest=${TEST_CLASSES}" -DfailIfNoTests=false \
            -Dsurefire.failIfNoSpecifiedTests=false) >"${WORK_LOG}" 2>&1; then
        pass "the characterisation suite passes in ${SPRINT_SIX_DIR}"
    else
        printf '\n'
        tail -n 25 "${WORK_LOG}" | sed 's/^/  | /'
        fail "The characterisation suite does not pass." \
            "A characterisation test that fails is telling you one of two" \
            "things: either it records behaviour the service never had, or the" \
            "change altered behaviour. Both are worth knowing and neither is" \
            "finished. A test you changed on purpose, because returning NEW" \
            "instead of a terminal status is a deliberate change, belongs in" \
            "the same commit as the change with a message that says so." \
            "Reproduce it with:" \
            "  cd ${SPRINT_SIX_PATH} && mvn test -Dtest=${TEST_CLASSES}"
    fi
fi

# --- the order the work happened in ------------------------------------------

section 'Tests before the change'

REPO_ROOT="$(git -C "${SPRINT_DIR}" rev-parse --show-toplevel 2>/dev/null || true)"

first_commit_for() {
    git -C "${REPO_ROOT}" log --reverse --format=%H -- "$@" 2>/dev/null | head -n 1
}

if [ -z "${REPO_ROOT}" ]; then
    skip "the ordering check: ${SPRINT_DIR} is not inside a Git repository."
    note "the rule is that the characterisation tests are committed before any"
    note "commit that changes your Sprint 6 sources. Without a history there is"
    note "nothing to read it from."
elif [ "${#CHARACTERISATION_FILES[@]}" -eq 0 ]; then
    skip "the ordering check: there are no characterisation tests to order, reported above."
else
    SPRINT_ARRIVED="$(first_commit_for "${SPRINT_DIR}")"
    TESTS_ADDED="$(first_commit_for "${CHARACTERISATION_PATH}")"

    if [ -z "${SPRINT_ARRIVED}" ]; then
        skip "the ordering check: no commit in this history touches ${SPRINT_DIR##*/}."
        note "that usually means the sprint folder arrived by copy rather than"
        note "by clone. Commit it, then the rule can be read."
    elif [ -z "${TESTS_ADDED}" ]; then
        fail "The characterisation tests exist on disk and in no commit." \
            "The rule is read from the history, so a test that is not" \
            "committed cannot satisfy it. Commit them before you change the" \
            "service."
    else
        SIX_FIRST_CHANGE="$(git -C "${REPO_ROOT}" log --reverse --format=%H \
            "${SPRINT_ARRIVED}..HEAD" -- "${SPRINT_SIX_SRC}" 2>/dev/null | head -n 1 || true)"

        if [ -z "${SIX_FIRST_CHANGE}" ]; then
            pass "the characterisation tests are committed and your Sprint 6 sources are unchanged since this sprint began"
            note "the ordering rule holds so far because nothing has changed the"
            note "service yet. The tests are the first half of the deliverable"
            note "and publishing to ${ORDERS_TOPIC} is the second."
        elif [ "${TESTS_ADDED}" = "${SIX_FIRST_CHANGE}" ]; then
            fail "The characterisation tests and the first change to your Sprint 6 sources are the same commit." \
                "Commit: $(git -C "${REPO_ROOT}" log -1 --format='%h %s' "${TESTS_ADDED}")" \
                "Before means before. Tests written alongside a change record" \
                "what the code does after the change, which is the one thing" \
                "they cannot be used to check." \
                "Split the commit: the tests against the service as it stands," \
                "then the change."
        elif git -C "${REPO_ROOT}" merge-base --is-ancestor "${TESTS_ADDED}" "${SIX_FIRST_CHANGE}" 2>/dev/null; then
            pass "the characterisation tests were committed before the first change to ${SPRINT_SIX_DIR}/src/main/java"
            note "tests   $(git -C "${REPO_ROOT}" log -1 --format='%h %ad %s' --date=short "${TESTS_ADDED}")"
            note "change  $(git -C "${REPO_ROOT}" log -1 --format='%h %ad %s' --date=short "${SIX_FIRST_CHANGE}")"
        else
            fail "Your Sprint 6 sources were changed before the characterisation tests were committed." \
                "change  $(git -C "${REPO_ROOT}" log -1 --format='%h %ad %s' --date=short "${SIX_FIRST_CHANGE}")" \
                "tests   $(git -C "${REPO_ROOT}" log -1 --format='%h %ad %s' --date=short "${TESTS_ADDED}")" \
                "The rule, exactly: the first commit that adds a file under" \
                "${CHARACTERISATION_TEST_DIR} has to be a proper ancestor of" \
                "the first commit, after this sprint folder arrived in the" \
                "repository, that changes anything under" \
                "${SPRINT_SIX_DIR}/src/main/java." \
                "It is not bureaucracy. A test written after a change records" \
                "the behaviour of the changed code, so it cannot tell you" \
                "whether the change altered anything. That is the whole purpose" \
                "of the technique, and the history is the only evidence that it" \
                "was used."
        fi
    fi
fi

# --- live mode ---------------------------------------------------------------

if [ "${LIVE}" -eq 1 ]; then

    SERVICE_URL="http://${SERVICE_HOST}:${SERVICE_PORT}"
    AUTH_URL="http://${AUTH_HOST}:${AUTH_PORT}"
    TAB="$(printf '\t')"

    HTTP_STATUS=""
    HTTP_BODY=""

    request() {
        req_method="$1"
        req_url="$2"
        req_token="$3"
        req_body="$4"

        req_args=(-s -o "${RESP_BODY}" -w '%{http_code}' --max-time 20 -X "${req_method}" "${req_url}")
        [ -n "${req_token}" ] && req_args+=(-H "Authorization: Bearer ${req_token}")
        if [ -n "${req_body}" ]; then
            req_args+=(-H 'Content-Type: application/json' --data "${req_body}")
        fi

        if HTTP_STATUS="$(curl "${req_args[@]}" 2>/dev/null)"; then
            :
        else
            HTTP_STATUS="000"
        fi
        HTTP_BODY="$(tr -d '\r\n' <"${RESP_BODY}")"
    }

    json_field() {
        printf '%s' "$1" | python3 -c 'import json,sys
try:
    data = json.load(sys.stdin)
except Exception:
    raise SystemExit(0)
if isinstance(data, dict):
    value = data.get(sys.argv[1])
    if value is not None:
        print(value)
' "$2" 2>/dev/null || true
    }

    status_of_order() {
        printf '%s' "$1" | python3 -c 'import json,sys
want = sys.argv[1]
try:
    data = json.load(sys.stdin)
except Exception:
    raise SystemExit(0)
if not isinstance(data, list):
    raise SystemExit(0)
for row in data:
    if not isinstance(row, dict):
        continue
    for key in ("orderId", "id", "order_id"):
        value = row.get(key)
        if value and str(value).replace("ORD-", "") == want:
            print(row.get("status", ""))
            raise SystemExit(0)
' "$2" 2>/dev/null || true
    }

    order_body() {
        printf '{"accountId":%s,"symbol":"%s","side":"BUY","quantity":%s,"price":%s,"idempotencyKey":"%s"}' \
            "$1" "$2" "$3" "$4" "$5"
    }

    balance_now() {
        request GET "${SERVICE_URL}/api/v1/accounts/${LIVE_ACTIVE_ACCOUNT_ID}/balance" "${TOKEN}" ""
        json_field "${HTTP_BODY}" cashBalance
    }

    kafka_cli() {
        kafka_tool="$1"
        shift
        if [ -n "${KAFKA_CONTAINER}" ]; then
            docker exec -i "${KAFKA_CONTAINER}" "${KAFKA_BIN}/${kafka_tool}" \
                --bootstrap-server "${KAFKA_BOOTSTRAP}" "$@"
        else
            "${KAFKA_BIN}/${kafka_tool}" --bootstrap-server "${KAFKA_BOOTSTRAP}" "$@"
        fi
    }

    psql_exec() {
        if [ -n "${POSTGRES_CONTAINER}" ]; then
            docker exec -i "${POSTGRES_CONTAINER}" \
                psql -v ON_ERROR_STOP=1 -U "${PG_USER}" -d "${PG_DATABASE}" -c "$1"
        else
            psql -v ON_ERROR_STOP=1 -U "${PG_USER}" -d "${PG_DATABASE}" -c "$1"
        fi
    }

    # Drain a topic into ${CONSUMED}. The console consumer exits non-zero when
    # its timeout expires with nothing left to read, which is the normal way
    # for it to finish here rather than an error. The message cap is the other
    # way out: that timeout only fires on a gap in the stream, so a topic
    # somebody is publishing to steadily would otherwise never end the read.
    drain_topic() {
        kafka_cli kafka-console-consumer.sh --topic "$1" --from-beginning \
            --timeout-ms "$2" --max-messages "${3:-500}" --property print.key=true \
            --property "key.separator=${TAB}" >"${CONSUMED}" 2>/dev/null || true
    }

    # One line per partition, as topic:partition:offset, where the offset is
    # the next one that will be written. Two of these taken either side of a
    # wait say exactly which messages arrived in between, which is what makes
    # it possible to read those messages and nothing else.
    end_offsets() {
        kafka_cli kafka-get-offsets.sh --topic "$1" --time -1 2>/dev/null
    }

    section 'Live: the broker and the topics'

    KAFKA_OK=0
    if [ -n "${KAFKA_CONTAINER}" ] && ! command -v docker >/dev/null 2>&1; then
        skip "every broker probe: KAFKA_CONTAINER names ${KAFKA_CONTAINER} and docker is not on your PATH."
        note "set KAFKA_CONTAINER to an empty string and KAFKA_BIN to the"
        note "directory holding kafka-topics.sh if you run the broker outside"
        note "Docker."
    elif kafka_cli kafka-topics.sh --list >"${WORK_LOG}" 2>&1; then
        KAFKA_OK=1
        pass "the broker answers at ${KAFKA_BOOTSTRAP}"
    else
        tail -n 5 "${WORK_LOG}" | sed 's/^/  | /'
        skip "every broker probe: nothing answered at ${KAFKA_BOOTSTRAP}."
        note "start the infrastructure with docker compose up -d, and check"
        note "KAFKA_CONTAINER, KAFKA_BIN and KAFKA_BOOTSTRAP in manifest.env."
    fi

    if [ "${KAFKA_OK}" -eq 1 ]; then
        check_topic() {
            topic_name="$1"
            want_partitions="$2"
            if ! kafka_cli kafka-topics.sh --describe --topic "${topic_name}" >"${WORK_LOG}" 2>&1; then
                fail "The topic ${topic_name} does not exist." \
                    "The three topics are created explicitly at startup by" \
                    "infra/kafka/create-topics.sh, because auto-creation" \
                    "produces a one-partition topic with the wrong retention." \
                    "  docker compose run --rm kafka-init"
                return
            fi
            got_partitions="$(sed -n 's/.*PartitionCount:[[:space:]]*\([0-9][0-9]*\).*/\1/p' "${WORK_LOG}" | head -n 1)"
            if [ "${got_partitions}" = "${want_partitions}" ]; then
                pass "${topic_name} exists with ${got_partitions} partitions"
            else
                fail "${topic_name} has ${got_partitions:-an unreadable number of} partitions, and the contract says ${want_partitions}." \
                    "Partitions can be increased and never decreased, and" \
                    "increasing them rehashes keys, so an account's history" \
                    "splits across partitions from that point on." \
                    "A one-partition topic is what auto-creation produces. Drop" \
                    "it and create it from infra/kafka/create-topics.sh."
            fi
        }

        check_topic "${ORDERS_TOPIC}" "${ORDERS_PARTITIONS}"
        check_topic "${TRADE_EVENTS_TOPIC}" "${TRADE_EVENTS_PARTITIONS}"
        check_topic "${MARKET_DATA_TOPIC}" "${MARKET_DATA_PARTITIONS}"

        if kafka_cli kafka-consumer-groups.sh --list 2>/dev/null | grep -qx "${EXECUTOR_CONSUMER_GROUP}"; then
            pass "a consumer group named ${EXECUTOR_CONSUMER_GROUP} is known to the broker"
        else
            note "no consumer group named ${EXECUTOR_CONSUMER_GROUP} yet. The"
            note "group appears once your executor has joined it, so this is"
            note "expected before it starts and worth reading if the order"
            note "probes below hang at NEW."
        fi
    fi

    section 'Live: an order through the platform'

    request GET "${SERVICE_URL}/api/v1/accounts/${LIVE_ACTIVE_ACCOUNT_ID}" "" ""
    if [ "${HTTP_STATUS}" = "000" ]; then
        abort "Nothing answered at ${SERVICE_URL}." \
            "Live mode needs the whole platform up: the infrastructure, your" \
            "schema and seed data, the auth stub, your Trade REST API, your" \
            "executor and your poller." \
            "  docker compose --profile platform up -d --build" \
            "If your service listens elsewhere, correct SERVICE_HOST and" \
            "SERVICE_PORT in manifest.env."
    fi

    LOGIN_BODY="$(printf '{"username":"%s","password":"%s"}' "${LIVE_ACTIVE_USERNAME}" "${LIVE_PASSWORD}")"
    request POST "${AUTH_URL}/auth/login" "" "${LOGIN_BODY}"
    TOKEN="$(json_field "${HTTP_BODY}" accessToken)"
    if [ -z "${TOKEN}" ]; then
        abort "The auth stub at ${AUTH_URL} issued no token for ${LIVE_ACTIVE_USERNAME}." \
            "HTTP ${HTTP_STATUS}, body: ${HTTP_BODY:-empty}" \
            "  docker compose up -d auth-stub"
    fi
    pass "a token was issued for ${LIVE_ACTIVE_USERNAME}"

    BALANCE_BEFORE="$(balance_now)"
    PROBE_KEY="harness-$$-$(date +%s)"

    request POST "${SERVICE_URL}/api/v1/orders" "${TOKEN}" \
        "$(order_body "${LIVE_ACTIVE_ACCOUNT_ID}" "${LIVE_TRADABLE_SYMBOL}" \
            "${LIVE_PROBE_QUANTITY}" "${LIVE_PROBE_LIMIT_PRICE}" "${PROBE_KEY}")"

    ORDER_ID=""
    if [ "${HTTP_STATUS}" = "200" ]; then
        ORDER_ID="$(json_field "${HTTP_BODY}" orderId)"
        ORDER_ID="${ORDER_ID#ORD-}"
        PLACED_STATUS="$(json_field "${HTTP_BODY}" status)"
        if [ "${PLACED_STATUS}" = "NEW" ]; then
            pass "POST /api/v1/orders answered NEW for ${ORDER_ID}"
        else
            fail "POST /api/v1/orders answered ${PLACED_STATUS:-no status}, and from this sprint it has to answer NEW." \
                "Body: ${HTTP_BODY:-empty}" \
                "Sprint 6 filled the order inside the request and answered" \
                "FILLED or REJECTED. Sprint 7 separates the two: the service" \
                "records the order, publishes it, and answers NEW. The fill" \
                "arrives on ${TRADE_EVENTS_TOPIC} once the executor has done" \
                "the work." \
                "This is a small change to your own code: record, publish" \
                "after the commit, return NEW. It is not a rewrite."
        fi
    else
        fail "POST /api/v1/orders answered HTTP ${HTTP_STATUS} to an affordable order." \
            "Body: ${HTTP_BODY:-empty}" \
            "The probe buys ${LIVE_PROBE_QUANTITY} unit(s) of" \
            "${LIVE_TRADABLE_SYMBOL} at a limit of ${LIVE_PROBE_LIMIT_PRICE}." \
            "If that symbol is not tradable in your seed data, or the account" \
            "cannot afford it, correct LIVE_TRADABLE_SYMBOL," \
            "LIVE_PROBE_QUANTITY and LIVE_PROBE_LIMIT_PRICE in manifest.env." \
            "Everything after this depends on an order having been placed."
    fi

    ORDER_RECORD=""
    if [ "${KAFKA_OK}" -eq 1 ] && [ -n "${ORDER_ID}" ]; then
        drain_topic "${ORDERS_TOPIC}" 15000
        ORDER_RECORD="$(grep -F "${ORDER_ID}" "${CONSUMED}" | head -n 1 || true)"
        if [ -n "${ORDER_RECORD}" ]; then
            RECORD_KEY="${ORDER_RECORD%%"${TAB}"*}"
            pass "the order reached ${ORDERS_TOPIC}, keyed ${RECORD_KEY}"
            if [ "${RECORD_KEY}" = "${LIVE_ACTIVE_ACCOUNT_ID}" ]; then
                pass "the key is the accountId, so one account's orders stay on one partition"
            else
                fail "The message on ${ORDERS_TOPIC} is keyed ${RECORD_KEY} and the contract keys it by accountId as a string." \
                    "The key decides the partition and the partition decides the" \
                    "ordering. Keyed by anything per-order, every message lands" \
                    "on its own partition and a sell can be executed before the" \
                    "buy that made it possible. Keyed by nothing, the producer" \
                    "round-robins and the same thing happens."
            fi
        else
            fail "No message carrying ${ORDER_ID} on ${ORDERS_TOPIC}." \
                "The order was accepted, so it is in your database and nothing" \
                "told the rest of the platform. Publish after the commit and" \
                "before the response: publishing inside the transaction risks" \
                "an event for an order that rolled back, and that is the one" \
                "failure nothing can undo." \
                "The harness read the topic from the beginning for 15 seconds."
        fi
    elif [ -n "${ORDER_ID}" ]; then
        skip "reading ${ORDERS_TOPIC}: the broker probes were skipped, reported above."
    fi

    TERMINAL_STATUS=""
    if [ -n "${ORDER_ID}" ]; then
        STARTED_AT="$(date +%s)"
        DEADLINE=$(( STARTED_AT + EXECUTION_TIMEOUT_SECONDS ))
        while [ "$(date +%s)" -lt "${DEADLINE}" ]; do
            request GET "${SERVICE_URL}/api/v1/accounts/${LIVE_ACTIVE_ACCOUNT_ID}/orders" "${TOKEN}" ""
            CURRENT_STATUS="$(status_of_order "${HTTP_BODY}" "${ORDER_ID}")"
            case "${CURRENT_STATUS}" in
                FILLED|REJECTED|CANCELLED) TERMINAL_STATUS="${CURRENT_STATUS}"; break ;;
            esac
            sleep 3
        done
        WAITED=$(( $(date +%s) - STARTED_AT ))

        if [ -n "${TERMINAL_STATUS}" ]; then
            pass "the order reached ${TERMINAL_STATUS} after ${WAITED}s, so the executor consumed and settled it"
        else
            fail "The order was still ${CURRENT_STATUS:-unreadable} after ${EXECUTION_TIMEOUT_SECONDS}s." \
                "An order that never leaves NEW is the failure this sprint" \
                "makes possible and the one a customer notices. Look at the" \
                "executor's log, then at the consumer group's lag:" \
                "  ${KAFKA_BIN}/kafka-consumer-groups.sh --describe --group ${EXECUTOR_CONSUMER_GROUP}" \
                "A group with climbing lag is not keeping up. A group that is" \
                "not listed has not joined. An order stuck with zero lag means" \
                "the message was consumed and the settlement did not happen."
        fi
    fi

    section 'Live: the same order, delivered twice'

    if [ "${KAFKA_OK}" -ne 1 ] || [ -z "${ORDER_RECORD}" ]; then
        skip "the duplicate-replay probe: there is no captured order message to replay."
        note "this is the demonstration the sprint is assessed on. Once the"
        note "probes above pass, run it by hand: read one message off"
        note "${ORDERS_TOPIC}, produce it again with the same key, and watch"
        note "the balance."
    elif [ -z "${TERMINAL_STATUS}" ]; then
        skip "the duplicate-replay probe: the first delivery has not settled, so a second proves nothing."
    else
        BALANCE_ONCE="$(balance_now)"
        drain_topic "${TRADE_EVENTS_TOPIC}" 15000
        EVENTS_ONCE="$(grep -c -F "${ORDER_ID}" "${CONSUMED}" || true)"

        if [ "${EVENTS_ONCE}" -ge 1 ]; then
            pass "${EVENTS_ONCE} event(s) for this order on ${TRADE_EVENTS_TOPIC}"
        else
            fail "Nothing on ${TRADE_EVENTS_TOPIC} mentions ${ORDER_ID}." \
                "The order settled and told nobody. A rejection is an event" \
                "too: the blotter, notifications and analytics all need to know" \
                "an order failed, and a consumer that only ever sees fills" \
                "reports a fill rate of 100 per cent."
        fi

        printf '%s\n' "${ORDER_RECORD}" \
            | kafka_cli kafka-console-producer.sh --topic "${ORDERS_TOPIC}" \
                --property parse.key=true --property "key.separator=${TAB}" \
                >/dev/null 2>&1 \
            && REPLAYED=1 || REPLAYED=0

        if [ "${REPLAYED}" -ne 1 ]; then
            skip "the duplicate-replay probe: the message could not be produced back to ${ORDERS_TOPIC}."
        else
            pass "the same message was delivered to ${ORDERS_TOPIC} a second time"

            # Bounded by the clock rather than by the sleeps, because reading
            # the topic between attempts costs time of its own.
            DEADLINE=$(( $(date +%s) + EXECUTION_TIMEOUT_SECONDS ))
            BALANCE_TWICE="${BALANCE_ONCE}"
            EVENTS_TWICE="${EVENTS_ONCE}"
            while [ "$(date +%s)" -lt "${DEADLINE}" ]; do
                sleep 3
                BALANCE_TWICE="$(balance_now)"
                drain_topic "${TRADE_EVENTS_TOPIC}" 8000
                EVENTS_TWICE="$(grep -c -F "${ORDER_ID}" "${CONSUMED}" || true)"
                if [ "${BALANCE_TWICE}" != "${BALANCE_ONCE}" ] || [ "${EVENTS_TWICE}" != "${EVENTS_ONCE}" ]; then
                    break
                fi
            done

            if [ "${TERMINAL_STATUS}" != "FILLED" ]; then
                skip "the double-debit check: the order came back ${TERMINAL_STATUS}, so no cash moved the first time."
                note "a rejected order is a weak subject for this probe. Point"
                note "LIVE_PROBE_LIMIT_PRICE at something a live quote clears so"
                note "that the replay has money to move, then run it again."
            elif [ "${BALANCE_TWICE}" = "${BALANCE_ONCE}" ]; then
                pass "the balance is unchanged at ${BALANCE_TWICE} after the replay"
            else
                fail "The account was debited twice. Balance ${BALANCE_ONCE} before the replay, ${BALANCE_TWICE} after it." \
                    "The platform runs at-least-once. Producers retry," \
                    "consumers commit after processing, and duplicates happen." \
                    "They are not worth trying to eliminate, and they are the" \
                    "reason the settlement has to be idempotent." \
                    "Make the first write of the transaction a guarded" \
                    "transition rather than a read: update the order to its new" \
                    "status only where it still holds the status you expect," \
                    "and treat zero rows affected as work somebody else already" \
                    "did. Nothing after that statement runs on a duplicate." \
                    "Balance before the order was placed: ${BALANCE_BEFORE:-unread}."
            fi

            if [ "${EVENTS_TWICE}" = "${EVENTS_ONCE}" ]; then
                pass "no second event for this order on ${TRADE_EVENTS_TOPIC}"
            else
                fail "The replay produced ${EVENTS_TWICE} events for one order, up from ${EVENTS_ONCE}." \
                    "Every consumer of ${TRADE_EVENTS_TOPIC} now believes the" \
                    "order happened twice, including the analytics load and, in" \
                    "Sprint 10, the portfolio projection." \
                    "A duplicate delivery has to return having changed nothing" \
                    "and published nothing."
            fi
        fi
    fi

    section 'Live: quotes on the bus'

    if [ "${KAFKA_OK}" -ne 1 ]; then
        skip "the market-data probe: the broker probes were skipped, reported above."
    else
        end_offsets "${MARKET_DATA_TOPIC}" >"${OFF_BEFORE}"
        sleep $(( POLL_INTERVAL_SECONDS + 15 ))
        end_offsets "${MARKET_DATA_TOPIC}" >"${OFF_AFTER}"

        # Read back exactly the messages that arrived in that window, partition
        # by partition, rather than whatever the topic happened to hold first.
        : >"${CONSUMED}"
        QUOTE_COUNT=0
        while IFS=: read -r _topic partition after_offset; do
            [ -n "${partition:-}" ] || continue
            before_offset="$(awk -F: -v p="${partition}" '$2 == p { print $3 }' "${OFF_BEFORE}")"
            before_offset="${before_offset:-0}"
            arrived=$(( after_offset - before_offset ))
            [ "${arrived}" -gt 0 ] || continue
            QUOTE_COUNT=$(( QUOTE_COUNT + arrived ))
            [ "${arrived}" -gt 50 ] && arrived=50
            # </dev/null matters: the consumer reads standard input, and
            # standard input here is the file this loop is reading from.
            kafka_cli kafka-console-consumer.sh --topic "${MARKET_DATA_TOPIC}" \
                --partition "${partition}" --offset "${before_offset}" \
                --max-messages "${arrived}" --timeout-ms 10000 \
                --property print.key=true --property "key.separator=${TAB}" \
                >>"${CONSUMED}" 2>/dev/null </dev/null || true
        done <"${OFF_AFTER}"

        DISTINCT_SYMBOLS="$(cut -f1 "${CONSUMED}" | LC_ALL=C sort -u | grep -c . || true)"

        if [ "${QUOTE_COUNT}" -ge 1 ]; then
            pass "${QUOTE_COUNT} quote(s) arrived on ${MARKET_DATA_TOPIC} within one polling interval"
        else
            fail "The end offsets on ${MARKET_DATA_TOPIC} did not move in ${POLL_INTERVAL_SECONDS}s plus 15s of slack." \
                "The topic is empty, so there is no price stream, and every" \
                "Sprint 10 extension that reads prices has nothing to consume." \
                "Check that the poller is running, that it has a Fauxnance key," \
                "and that it has not spent its request budget. GET /usage on" \
                "the API reports what the key has spent today."
        fi

        if [ "${DISTINCT_SYMBOLS}" -gt 1 ]; then
            pass "${DISTINCT_SYMBOLS} distinct symbols across one cycle of messages, each as its own message"
            note "that is evidence of a batched call, not proof of one. Whether"
            note "the batch is capped at 25 and what the quota arithmetic comes"
            note "to is read from your code and your notes at the review."
        elif [ "${QUOTE_COUNT}" -ge 1 ]; then
            note "every message read carried the same key. That is"
            note "correct for a one-symbol watchlist and wrong for anything"
            note "else: one message per symbol, keyed by symbol, never one"
            note "message per batch."
        fi
    fi

    section 'Live: the batch load'

    run_command() {
        (cd "${SPRINT_DIR}" && bash -c "$1")
    }

    count_from() {
        run_command "$1" 2>/dev/null | tr -d '[:space:]'
    }

    FACT_BEFORE="$(count_from "${ETL_FACT_COUNT_COMMAND}" || true)"
    if ! printf '%s' "${FACT_BEFORE}" | grep -qE '^[0-9]+$'; then
        skip "every pipeline probe: ETL_FACT_COUNT_COMMAND printed '${FACT_BEFORE:-nothing}' rather than a number."
        note "the harness has no idea what your analytical store is, so it asks"
        note "you for three commands. The count commands print one integer and"
        note "nothing else. Worked examples are in manifest.env."
    else
        if run_command "${ETL_RUN_COMMAND}" >"${WORK_LOG}" 2>&1; then
            pass "ETL_RUN_COMMAND completed"
        else
            printf '\n'
            tail -n 20 "${WORK_LOG}" | sed 's/^/  | /'
            fail "ETL_RUN_COMMAND exited non-zero." \
                "Reproduce it with:" \
                "  cd ${SPRINT_DIR} && ${ETL_RUN_COMMAND}"
        fi

        FACT_AFTER="$(count_from "${ETL_FACT_COUNT_COMMAND}" || true)"
        if ! printf '%s' "${FACT_AFTER}" | grep -qE '^[0-9]+$'; then
            fail "ETL_FACT_COUNT_COMMAND stopped printing a number after the load: '${FACT_AFTER:-nothing}'."
        elif [ "${FACT_AFTER}" -gt "${FACT_BEFORE}" ]; then
            pass "fact_trades grew from ${FACT_BEFORE} to ${FACT_AFTER} rows"
        else
            fail "fact_trades held ${FACT_BEFORE} rows before the load and ${FACT_AFTER} after it." \
                "An order was placed and settled during this run, so there was" \
                "at least one new row to load. A load that finds nothing" \
                "usually means the watermark moved past the data, or the" \
                "extract query filters on a status the order has not reached." \
                "Rejected and cancelled orders are loaded too. Fill rate is one" \
                "of the analytics the model has to answer and it cannot be" \
                "computed from fills alone."
        fi

        IDEMPOTENT=0
        FACT_TWICE=""
        if printf '%s' "${FACT_AFTER}" | grep -qE '^[0-9]+$'; then
            run_command "${ETL_RUN_COMMAND}" >"${WORK_LOG}" 2>&1 || true
            FACT_TWICE="$(count_from "${ETL_FACT_COUNT_COMMAND}" || true)"
            if [ "${FACT_TWICE}" = "${FACT_AFTER}" ]; then
                IDEMPOTENT=1
                pass "running the load a second time left fact_trades at ${FACT_TWICE} rows"
            else
                fail "A second load with no new data took fact_trades from ${FACT_AFTER} to ${FACT_TWICE} rows." \
                    "Re-running yesterday's load must not double-count. Every" \
                    "number the dashboard reports is now wrong by however many" \
                    "times the pipeline has run, and nothing in the warehouse" \
                    "records which rows are the duplicates." \
                    "Merge on the natural key rather than inserting:" \
                    "source_order_id is unique per order, and the unique" \
                    "constraint on it in contracts/analytics-schema.sql is what" \
                    "makes that enforceable in the store as well as in the" \
                    "pipeline."
            fi
        fi

        # A fresh identifier every run, substituted into both statements, so
        # that a row a previous run planted cannot be mistaken for this one and
        # a dead-letter store that merges on the order key still shows a change.
        BAD_ROW_ID="$(python3 -c 'import uuid; print(uuid.uuid4())')"
        BAD_ROW_INSERT="${ETL_BAD_ROW_INSERT_SQL//HARNESS_BAD_ROW_ID/${BAD_ROW_ID}}"
        BAD_ROW_CLEANUP="${ETL_BAD_ROW_CLEANUP_SQL//HARNESS_BAD_ROW_ID/${BAD_ROW_ID}}"

        DLQ_BEFORE="$(count_from "${ETL_DEAD_LETTER_COUNT_COMMAND}" || true)"
        if ! printf '%s' "${DLQ_BEFORE}" | grep -qE '^[0-9]+$'; then
            skip "the dead-letter probe: ETL_DEAD_LETTER_COUNT_COMMAND printed '${DLQ_BEFORE:-nothing}' rather than a number."
            note "a row that fails a pre-load check has to land somewhere with"
            note "the reason it failed. Silently dropping it means a load that"
            note "reports success and a warehouse that quietly disagrees with"
            note "the operational database."
        elif ! psql_exec "${BAD_ROW_INSERT}" >"${WORK_LOG}" 2>&1; then
            tail -n 5 "${WORK_LOG}" | sed 's/^/  | /'
            skip "the dead-letter probe: the planted row would not go into your schema."
            note "correct ETL_BAD_ROW_INSERT_SQL in manifest.env to your table"
            note "and column names. The row has to be one your operational"
            note "constraints accept and your pipeline must not."
        else
            run_command "${ETL_RUN_COMMAND}" >"${WORK_LOG}" 2>&1 || true
            DLQ_AFTER="$(count_from "${ETL_DEAD_LETTER_COUNT_COMMAND}" || true)"
            FACT_WITH_BAD="$(count_from "${ETL_FACT_COUNT_COMMAND}" || true)"

            if printf '%s' "${DLQ_AFTER}" | grep -qE '^[0-9]+$' && [ "${DLQ_AFTER}" -gt "${DLQ_BEFORE}" ]; then
                pass "the planted row was dead-lettered: ${DLQ_BEFORE} to ${DLQ_AFTER}"
            else
                fail "The planted row did not reach the dead-letter path: ${DLQ_BEFORE} before, ${DLQ_AFTER:-unreadable} after." \
                    "The row the harness planted satisfies every constraint the" \
                    "operational database enforces and none of the checks the" \
                    "analytical model needs. A pipeline that drops it silently" \
                    "and one that dead-letters it both produce the same fact" \
                    "table; only one of them can be investigated on Monday" \
                    "morning." \
                    "Record the row, the reason and the batch it came from."
            fi

            if [ "${IDEMPOTENT}" -ne 1 ]; then
                skip "checking that the planted row stayed out of fact_trades: the load is not idempotent, so the count cannot isolate one row."
            elif [ "${FACT_WITH_BAD}" = "${FACT_TWICE}" ]; then
                pass "fact_trades is unchanged at ${FACT_WITH_BAD}, so the planted row was not loaded"
            else
                fail "fact_trades went from ${FACT_TWICE} to ${FACT_WITH_BAD} rows, and the only new source row was the planted one." \
                    "It was loaded. A row that fails a check belongs in the" \
                    "dead-letter path and nowhere else. Inserting it with a" \
                    "placeholder dimension key to make the load pass hides the" \
                    "fault instead of reporting it."
            fi

            if psql_exec "${BAD_ROW_CLEANUP}" >/dev/null 2>&1; then
                note "the planted row has been removed from the operational database."
            else
                note "the planted row could not be removed. Run"
                note "ETL_BAD_ROW_CLEANUP_SQL from manifest.env by hand."
            fi
        fi
    fi
fi

# --- result ------------------------------------------------------------------

printf '\n%s\n' '----------------------------------------------------------------'
printf '%s passed, %s failed\n' "${PASSED}" "${FAILED}"

if [ "${KEEP_VENV}" -eq 1 ]; then
    printf 'Scratch environment %s kept, as asked.\n' "${VENV_DIR}"
elif [ "${FAILED}" -eq 0 ]; then
    rm -rf "${VENV_DIR}"
    printf 'Scratch environment removed.\n'
else
    printf 'Scratch environment %s left in place so you can run pytest in it.\n' "${VENV_DIR}"
fi

if [ "${FAILED}" -eq 0 ]; then
    if [ "${LIVE}" -eq 0 ]; then
        printf '\nThe harness is satisfied by the static checks. It has read your\n'
        printf 'builds, your tests, your commit history and every file in this\n'
        printf 'folder, and it has never sent a message. Run it again with --live\n'
        printf 'once the whole stack is up.\n'
    else
        printf '\nThe harness is satisfied. It has placed one order, watched it\n'
        printf 'settle, delivered the same message twice and found the balance\n'
        printf 'unmoved, waited for a quote, and run your pipeline around a row it\n'
        printf 'planted.\n'
    fi
    printf '\nAssessed by a human at the review: the fill rule and what it does at\n'
    printf 'the boundaries, whether the transaction encloses the three writes and\n'
    printf 'nothing more, whether the retry and dead-letter split distinguishes a\n'
    printf 'poison message from a transient failure, the quota arithmetic, the\n'
    printf 'SonarQube gate, and whether the characterisation tests pin behaviour\n'
    printf 'worth pinning.\n'
    exit 0
fi

printf '\nEach failure above says what was expected and where to look. The\n'
printf 'SonarQube gate, the fill rule and the quality of the characterisation\n'
printf 'tests are assessed at the review, not here.\n'

exit 1
