#!/usr/bin/env bash
#
# Sprint 9 acceptance harness.
#
#   check.sh              static checks only. No browser, no running stack.
#   check.sh --live       the static checks, then the journeys and the probes
#                         against your running stack.
#   check.sh --reuse      reuse the installed node_modules instead of running
#                         npm ci again. Faster, and it stops proving that the
#                         lock file installs.
#
# Static mode installs from the lock file, builds the production bundle, reads
# your generated clients and regenerates them from the contracts to prove they
# have not drifted, runs your unit suite and reads the names of the tests that
# ran, checks every error code in the contracts against your mapping, and greps
# the built bundle for a key, a secret and the market-data address.
#
# Live mode needs your stack up: this application served, your Trade REST API
# and your Auth service. It runs each of the three journeys separately, drives
# your sign-in form, watches an unauthenticated visit to a guarded route, and
# records every request the browser makes to see where the bearer token goes.
# Live mode starts nothing and stops nothing.
#
# Both modes read your names from manifest.env, so the harness asserts your
# design rather than dictating one.
#
# Passing these checks is necessary and not sufficient. Whether the messages
# your mapping produces are readable by a trader, whether the interceptor
# decides by origin rather than by a list of hosts somebody remembered, and
# whether the blotter tells a working order apart from a stalled one are
# assessed at the review.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPRINT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
MANIFEST="${SPRINT_DIR}/manifest.env"

LIVE=0
REUSE=0
while [ "$#" -gt 0 ]; do
    case "$1" in
        --live) LIVE=1; shift ;;
        --reuse) REUSE=1; shift ;;
        -h|--help) sed -n '2,26p' "${BASH_SOURCE[0]}" | sed 's/^#\{1,2\} \{0,1\}//'; exit 0 ;;
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

printf 'Sprint 9 acceptance harness\n'
if [ "${LIVE}" -eq 1 ]; then
    printf 'Static checks, then the journeys and probes against your running stack.\n'
else
    printf 'Static checks only. Add --live once your stack is up.\n'
fi

# --- the manifest ----------------------------------------------------------------

section 'Manifest'

[ -f "${MANIFEST}" ] || abort \
    "No manifest.env in ${SPRINT_DIR}." \
    "The harness reads your paths, your test-name patterns, your selectors and" \
    "the addresses live mode needs from that file. If you have deleted it," \
    "restore it from the repository."

SRC_DIR=""
DIST_DIR=""
E2E_DIR=""
GENERATOR_CONFIG=""
GENERATED_CLIENT_DIR=""
GENERATOR_MARKER=""
GENERATED_IMPORT_TOKEN=""
CONTRACTS_DIR=""
CONTRACT_FILES=""
ERROR_MAPPING_FILE=""
INTERCEPTOR_FILE=""
INTERCEPTOR_SPEC_PATTERN=""
INTERCEPTOR_ATTACH_TEST_PATTERN=""
INTERCEPTOR_NO_ATTACH_TEST_PATTERN=""
BUNDLE_API_KEY_PATTERN=""
BUNDLE_FAUXNANCE_URL_PATTERN=""
BUNDLE_SECRET_PATTERN=""
ROOT_ENV_FILE=""
UI_BASE_URL=""
TRADE_API_BASE_URL=""
AUTH_API_BASE_URL=""
E2E_LOGIN_SPEC=""
E2E_PLACE_ORDER_SPEC=""
E2E_HISTORY_SPEC=""
DEMO_USERNAME=""
DEMO_PASSWORD=""
DEMO_ACCOUNT_ID=""
DEMO_SYMBOL=""
GUARDED_ROUTE=""
LOGIN_ROUTE=""
LOGIN_USERNAME_SELECTOR=""
LOGIN_PASSWORD_SELECTOR=""
LOGIN_SUBMIT_SELECTOR=""
LOGIN_THROTTLE_COOLDOWN_SECONDS=""

# shellcheck source=/dev/null
. "${MANIFEST}"

STATIC_KEYS="SRC_DIR DIST_DIR E2E_DIR GENERATOR_CONFIG GENERATED_CLIENT_DIR
GENERATOR_MARKER GENERATED_IMPORT_TOKEN CONTRACTS_DIR CONTRACT_FILES
ERROR_MAPPING_FILE INTERCEPTOR_FILE INTERCEPTOR_SPEC_PATTERN
INTERCEPTOR_ATTACH_TEST_PATTERN INTERCEPTOR_NO_ATTACH_TEST_PATTERN
BUNDLE_API_KEY_PATTERN BUNDLE_FAUXNANCE_URL_PATTERN BUNDLE_SECRET_PATTERN"

LIVE_KEYS="UI_BASE_URL TRADE_API_BASE_URL AUTH_API_BASE_URL E2E_LOGIN_SPEC
E2E_PLACE_ORDER_SPEC E2E_HISTORY_SPEC DEMO_USERNAME DEMO_PASSWORD
DEMO_ACCOUNT_ID DEMO_SYMBOL GUARDED_ROUTE LOGIN_ROUTE LOGIN_USERNAME_SELECTOR
LOGIN_PASSWORD_SELECTOR LOGIN_SUBMIT_SELECTOR LOGIN_THROTTLE_COOLDOWN_SECONDS"

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
        "Every key that has a defensible default ships with one. Set the ones" \
        "your team decided differently and leave the rest alone. The only key" \
        "documented as optional is ROOT_ENV_FILE, and an empty value there" \
        "turns one search into a named skip."
fi

case "${GUARDED_ROUTE}" in /*) ;; *) abort "GUARDED_ROUTE has to start with a slash: ${GUARDED_ROUTE}" ;; esac
case "${LOGIN_ROUTE}" in /*) ;; *) abort "LOGIN_ROUTE has to start with a slash: ${LOGIN_ROUTE}" ;; esac

if [ -n "${LOGIN_THROTTLE_COOLDOWN_SECONDS}" ]; then
    printf '%s' "${LOGIN_THROTTLE_COOLDOWN_SECONDS}" | grep -qE '^[0-9]+$' || abort \
        "LOGIN_THROTTLE_COOLDOWN_SECONDS in manifest.env is not a whole number: ${LOGIN_THROTTLE_COOLDOWN_SECONDS}"
fi

pass "manifest.env declares every name the harness needs"

SRC_PATH="${SPRINT_DIR}/${SRC_DIR}"
DIST_PATH="${SPRINT_DIR}/${DIST_DIR}"
E2E_PATH="${SPRINT_DIR}/${E2E_DIR}"
GENERATED_PATH="${SPRINT_DIR}/${GENERATED_CLIENT_DIR}"
CONTRACTS_PATH="${SPRINT_DIR}/${CONTRACTS_DIR}"
MAPPING_PATH="${SPRINT_DIR}/${ERROR_MAPPING_FILE}"
INTERCEPTOR_PATH="${SPRINT_DIR}/${INTERCEPTOR_FILE}"

# --- files on disk -----------------------------------------------------------------

section 'Deliverables on disk'

for required in package.json angular.json playwright.config.ts "${GENERATOR_CONFIG}"; do
    [ -f "${SPRINT_DIR}/${required}" ] || abort \
        "No ${required} in ${SPRINT_DIR}." \
        "It ships with the scaffold. Restore it from the repository, or correct" \
        "manifest.env if you moved it deliberately."
done
pass "package.json, angular.json, playwright.config.ts and ${GENERATOR_CONFIG} are present"

[ -d "${SRC_PATH}" ] || abort \
    "No ${SRC_DIR} directory in ${SPRINT_DIR}." \
    "SRC_DIR in manifest.env says ${SRC_DIR}. Either correct it or put your" \
    "sources there."

SOURCE_COUNT="$(find "${SRC_PATH}" -type f -name '*.ts' ! -name '*.d.ts' \
    ! -path "${GENERATED_PATH}/*" 2>/dev/null | wc -l | tr -d ' ')"

if [ "${SOURCE_COUNT}" -ge 2 ]; then
    pass "${SRC_DIR} holds ${SOURCE_COUNT} hand-written TypeScript file(s)"
else
    abort "There is almost nothing under ${SRC_DIR} yet." \
        "The scaffold ships as a bootstrap that compiles and a set of empty" \
        "directories, each with a README saying what belongs in it. Every" \
        "component, service, guard, interceptor and route is yours to write." \
        "On day one of the sprint this is the expected result. Generate the" \
        "clients, write the sign-in screen, then come back."
fi

# --- the toolchain -------------------------------------------------------------------

section 'Toolchain'

command -v node >/dev/null 2>&1 || abort \
    "node is not on your PATH." \
    "Install Node 20.19 or later. Angular 21 refuses to start below it."

command -v npm >/dev/null 2>&1 || abort "npm is not on your PATH. It ships with Node."

NODE_MAJOR="$(node -p 'process.versions.node.split(".")[0]' 2>/dev/null || printf '0')"
if [ "${NODE_MAJOR}" -ge 20 ]; then
    pass "node $(node -v) and npm $(npm -v) are on the PATH"
else
    abort "Node ${NODE_MAJOR} is older than the 20.19 this workspace declares." \
        "Angular 21 needs 20.19, 22.12 or 24 and above."
fi

if [ "${LIVE}" -eq 1 ]; then
    command -v curl >/dev/null 2>&1 || abort \
        "curl is not on your PATH, and live mode reaches your services with it."
fi

# --- installing and building -----------------------------------------------------------

section 'Installing and building'

BUILD_LOG="$(mktemp)"
TEST_JSON="$(mktemp)"
TEST_LIST="$(mktemp)"
PW_JSON="$(mktemp)"
SCRATCH="$(mktemp -d)"
PROBE_SPEC="${E2E_PATH}/zz-harness-probe.spec.ts"
trap 'rm -rf "${BUILD_LOG}" "${TEST_JSON}" "${TEST_LIST}" "${PW_JSON}" "${SCRATCH}" "${PROBE_SPEC}"' EXIT

INSTALL_OK=0
if [ "${REUSE}" -eq 1 ] && [ -d "${SPRINT_DIR}/node_modules" ]; then
    skip "npm ci: --reuse was given and node_modules is present."
    note "the run that counts installs from the lock file. Drop --reuse before"
    note "you call this deliverable finished."
    INSTALL_OK=1
elif [ ! -f "${SPRINT_DIR}/package-lock.json" ]; then
    fail "No package-lock.json in ${SPRINT_DIR}." \
        "npm ci installs exactly the tree the lock file names, which is what" \
        "makes your teammate's build the build you tested. The lock file ships" \
        "with the scaffold: restore it, and commit the new one whenever you add" \
        "a dependency." \
        "The harness fell back to npm install so that the rest could run."
    if (cd "${SPRINT_DIR}" && npm install --no-audit --no-fund) >"${BUILD_LOG}" 2>&1; then
        INSTALL_OK=1
    fi
else
    if (cd "${SPRINT_DIR}" && npm ci --no-audit --no-fund) >"${BUILD_LOG}" 2>&1; then
        pass "npm ci installs the tree the lock file names"
        INSTALL_OK=1
    else
        printf '\n'
        tail -n 25 "${BUILD_LOG}" | sed 's/^/  | /'
        fail "npm ci does not succeed." \
            "The output above is the tail of the install. Reproduce it with:" \
            "  cd ${SPRINT_DIR} && npm ci" \
            "npm ci fails where npm install succeeds when package.json and" \
            "package-lock.json disagree, which happens when a dependency was" \
            "added by editing package.json by hand. Run npm install once to" \
            "reconcile them and commit both files."
    fi
fi

[ "${INSTALL_OK}" -eq 1 ] || abort \
    "Dependencies are not installed, so nothing else could run." \
    "Fix the install reported above and run the harness again."

rm -rf "${SPRINT_DIR}/dist"
if (cd "${SPRINT_DIR}" && npm run build) >"${BUILD_LOG}" 2>&1; then
    pass "npm run build produces a production bundle"
else
    printf '\n'
    tail -n 30 "${BUILD_LOG}" | sed 's/^/  | /'
    fail "The production build does not succeed." \
        "The output above is the tail of it. Reproduce it with:" \
        "  cd ${SPRINT_DIR} && npm run build" \
        "ng build defaults to the production configuration, which type-checks" \
        "every file under src/ including the generated clients, applies the" \
        "budgets in angular.json and swaps in src/environments/environment.ts." \
        "A workspace that only builds with --configuration development is not" \
        "a workspace Sprint 11 can deploy."
fi

if [ -d "${DIST_PATH}" ]; then
    pass "the bundle is where DIST_DIR says it is: ${DIST_DIR}"
else
    fail "No build output at ${DIST_DIR}." \
        "The Angular application builder writes dist/<project>/browser, and the" \
        "project name comes from angular.json. Correct DIST_DIR in manifest.env" \
        "if you renamed the project. The bundle scan below needs this path."
fi

# --- the generated clients ---------------------------------------------------------------

section 'Clients generated from the contracts'

GENERATORS="$(node -e '
    const fs = require("fs");
    const config = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    const generators = ((config || {})["generator-cli"] || {}).generators || {};
    for (const [key, entry] of Object.entries(generators)) {
        if (entry && entry.disabled) { continue; }
        process.stdout.write([key, entry.inputSpec || "", entry.output || ""].join("\t") + "\n");
    }
' "${SPRINT_DIR}/${GENERATOR_CONFIG}" 2>/dev/null || true)"

if [ -z "${GENERATORS}" ]; then
    fail "${GENERATOR_CONFIG} declares no generator." \
        "Criterion 4 is that the clients are generated from the contracts. The" \
        "configuration ships with two entries, one per contract, and the harness" \
        "reads them from that file so that it regenerates with exactly the" \
        "settings you generate with. Restore it, or declare your own."
else
    GEN_KEYS="$(printf '%s\n' "${GENERATORS}" | awk -F'\t' '{ print $1 }' | tr '\n' ' ')"
    pass "${GENERATOR_CONFIG} declares generator(s): ${GEN_KEYS% }"
fi

CLIENTS_ON_DISK=1
MARKED_FILES=0
GENERATED_TS=0

while IFS="$(printf '\t')" read -r gen_key gen_spec gen_out; do
    [ -n "${gen_key}" ] || continue

    spec_path="${SPRINT_DIR}/${gen_spec}"
    out_path="${SPRINT_DIR}/${gen_out}"

    if [ ! -f "${spec_path}" ]; then
        fail "The ${gen_key} generator reads ${gen_spec}, and that file is not there." \
            "The contracts live in ${CONTRACTS_DIR} relative to this folder and" \
            "are not yours to move."
        CLIENTS_ON_DISK=0
        continue
    fi

    if [ ! -d "${out_path}" ]; then
        fail "The ${gen_key} client is not on disk. Nothing at ${gen_out}." \
            "Generate it and commit the result:" \
            "  cd ${SPRINT_DIR} && npm run generate" \
            "The output is committed rather than ignored, so that the build" \
            "needs no Java runtime and a contract change arrives as a diff" \
            "somebody has to read."
        CLIENTS_ON_DISK=0
        continue
    fi

    out_ts="$(find "${out_path}" -type f -name '*.ts' 2>/dev/null | wc -l | tr -d ' ')"
    out_marked="$(grep -rliE "${GENERATOR_MARKER}" --include='*.ts' "${out_path}" 2>/dev/null \
        | wc -l | tr -d ' ')"
    GENERATED_TS=$((GENERATED_TS + out_ts))
    MARKED_FILES=$((MARKED_FILES + out_marked))

    if [ ! -f "${out_path}/.openapi-generator/VERSION" ]; then
        fail "${gen_out} carries no .openapi-generator/VERSION." \
            "The generator writes that file into everything it produces. A" \
            "client directory without it was assembled by hand, or the metadata" \
            "was deleted, and either way the freshness check below cannot mean" \
            "anything. Regenerate with npm run generate and commit the result."
        CLIENTS_ON_DISK=0
        continue
    fi

    if [ "${out_marked}" -lt 1 ]; then
        fail "No file under ${gen_out} carries the generator's header." \
            "GENERATOR_MARKER in manifest.env is ${GENERATOR_MARKER}." \
            "Hand-writing a client from a contract is rework the first time and" \
            "drift every time after it."
        CLIENTS_ON_DISK=0
        continue
    fi

    # Anything the generator did not write, sitting inside a directory the next
    # generation overwrites.
    STRAY=""
    while IFS= read -r found; do
        [ -n "${found}" ] || continue
        rel="${found#"${out_path}/"}"
        grep -qxF "${rel}" "${out_path}/.openapi-generator/FILES" 2>/dev/null || \
            STRAY="${STRAY} ${rel}"
    done < <(find "${out_path}" -type f -name '*.ts' 2>/dev/null | LC_ALL=C sort)

    if [ -n "${STRAY}" ]; then
        fail "${gen_out} holds file(s) the generator did not write:${STRAY}" \
            "The generator records what it produced in" \
            ".openapi-generator/FILES. A file in there that is not on that list" \
            "is a hand-written file inside a directory the next generation" \
            "overwrites. Move it into src/app/core/services/ and wrap the" \
            "generated client from outside."
        CLIENTS_ON_DISK=0
    fi
done <<EOF
${GENERATORS}
EOF

if [ "${CLIENTS_ON_DISK}" -eq 1 ] && [ -n "${GENERATORS}" ]; then
    pass "every declared client is on disk: ${GENERATED_TS} file(s), ${MARKED_FILES} carrying the generator header"
fi

# A generated client nothing imports is a directory.
if [ -d "${GENERATED_PATH}" ]; then
    IMPORTERS="$(grep -rlE "(from|import)[^\n]*['\"][^'\"]*${GENERATED_IMPORT_TOKEN}[^'\"]*['\"]" \
        --include='*.ts' "${SRC_PATH}" 2>/dev/null \
        | grep -v "^${GENERATED_PATH}/" | LC_ALL=C sort || true)"
    IMPORTER_COUNT="$(printf '%s' "${IMPORTERS}" | grep -c . || true)"

    if [ "${IMPORTER_COUNT}" -ge 1 ]; then
        pass "${IMPORTER_COUNT} file(s) outside the generated tree import the generated client"
    else
        fail "Nothing outside ${GENERATED_CLIENT_DIR} imports the generated client." \
            "The harness searched ${SRC_DIR} for an import specifier containing" \
            "${GENERATED_IMPORT_TOKEN}, which is GENERATED_IMPORT_TOKEN in" \
            "manifest.env, and found none." \
            "Generating a client and then calling HttpClient by hand beside it" \
            "leaves two descriptions of the same contract, and the one the" \
            "compiler checks is not the one in use. If your import looks" \
            "different from the default, correct the token."
    fi
fi

# The freshness check: regenerate into a temporary directory and diff.
if [ "${CLIENTS_ON_DISK}" -ne 1 ] || [ -z "${GENERATORS}" ]; then
    skip "the freshness check: there is no committed client to compare against."
elif ! command -v java >/dev/null 2>&1; then
    skip "the freshness check: java is not on your PATH."
    note "the generator runs on the JVM. You have a JDK from Sprint 5: put it"
    note "on the PATH and this check regenerates both clients into a temporary"
    note "directory and diffs them against the committed ones. Until then,"
    note "nothing here can tell a stale client from a current one."
else
    FRESH_DIR="${SCRATCH}/regenerated"
    mkdir -p "${FRESH_DIR}"

    # shellcheck disable=SC2016  # a node program, not a shell expansion
    node -e '
        const fs = require("fs");
        const path = require("path");
        const [configPath, sprintDir, target] = process.argv.slice(1);
        const config = JSON.parse(fs.readFileSync(configPath, "utf8"));
        const generators = config["generator-cli"].generators;
        for (const [key, entry] of Object.entries(generators)) {
            if (entry && entry.disabled) { continue; }
            entry.inputSpec = path.resolve(sprintDir, entry.inputSpec);
            entry.output = path.join(target, key);
        }
        delete config.$schema;
        fs.writeFileSync(path.join(target, "openapitools.json"), JSON.stringify(config, null, 2));
    ' "${SPRINT_DIR}/${GENERATOR_CONFIG}" "${SPRINT_DIR}" "${FRESH_DIR}"

    if (cd "${FRESH_DIR}" && "${SPRINT_DIR}/node_modules/.bin/openapi-generator-cli" generate) \
            >"${BUILD_LOG}" 2>&1; then
        DRIFT=""
        while IFS="$(printf '\t')" read -r gen_key gen_spec gen_out; do
            [ -n "${gen_key}" ] || continue
            [ -n "${gen_spec}" ] || continue
            if ! diff -r -q "${SPRINT_DIR}/${gen_out}" "${FRESH_DIR}/${gen_key}" \
                    >"${SCRATCH}/diff-${gen_key}" 2>&1; then
                DRIFT="${DRIFT} ${gen_key}"
            fi
        done <<EOF
${GENERATORS}
EOF

        if [ -z "${DRIFT}" ]; then
            pass "the committed clients are byte for byte what the contracts generate today"
        else
            fail "The contracts have moved ahead of the committed client(s):${DRIFT}" \
                "A fresh generation differs from what is in the repository, so" \
                "your typed client no longer describes the API your services" \
                "serve. Regenerate and commit:" \
                "  cd ${SPRINT_DIR} && npm run generate" \
                "Then build. Whatever stops compiling is the call site the" \
                "contract change affects, which is the whole reason for" \
                "generating rather than hand-writing. What differs:"
            for key in ${DRIFT}; do
                sed -n '1,12p' "${SCRATCH}/diff-${key}" | sed "s#${SPRINT_DIR}/##; s#${FRESH_DIR}#<freshly generated>#; s/^/        /"
            done
            printf '        %s\n' \
                "If the difference is an edit somebody made inside the generated" \
                "tree, the fix is the same: regenerate, and wrap the client from" \
                "outside instead."
        fi
    else
        printf '\n'
        tail -n 15 "${BUILD_LOG}" | sed 's/^/  | /'
        skip "the freshness check: the generator did not run."
        note "the output above is the tail of it. The generator downloads a JAR"
        note "on first use, so a machine with no network reaches this line."
        note "Reproduce with: cd ${SPRINT_DIR} && npm run generate"
    fi
fi

# --- the interceptor and its spec ----------------------------------------------------------

section 'The interceptor'

if [ -f "${INTERCEPTOR_PATH}" ]; then
    pass "${INTERCEPTOR_FILE} is present"
else
    fail "No interceptor at ${INTERCEPTOR_FILE}." \
        "Criterion 2 is one interceptor that attaches the bearer token to your" \
        "own APIs and to nothing else. INTERCEPTOR_FILE in manifest.env says" \
        "${INTERCEPTOR_FILE}: correct it if yours lives elsewhere." \
        "Attaching the header in each service instead means the day somebody" \
        "adds a service that forgets is the day a call goes out unauthenticated."
fi

# Which runner, from angular.json and package.json rather than from an assumption.
TEST_BUILDER="$(node -e '
    const fs = require("fs");
    const config = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    const projects = Object.values(config.projects || {});
    for (const project of projects) {
        const builder = (((project.architect || {}).test) || {}).builder;
        if (builder) { process.stdout.write(builder); break; }
    }
' "${SPRINT_DIR}/angular.json" 2>/dev/null || true)"

HAS_JEST=0
grep -q '"jest"' "${SPRINT_DIR}/package.json" 2>/dev/null && HAS_JEST=1

RUNNER=""
case "${TEST_BUILDER}" in
    *unit-test*) RUNNER="angular" ;;
    *karma*) RUNNER="karma" ;;
    *) [ "${HAS_JEST}" -eq 1 ] && RUNNER="jest" ;;
esac
if [ -z "${RUNNER}" ] && [ "${HAS_JEST}" -eq 1 ]; then RUNNER="jest"; fi

TEST_OK=0
REPORT_OK=0

NO_SPECS=0
SPEC_COUNT="$(find "${SRC_PATH}" -type f -name '*.spec.ts' 2>/dev/null | wc -l | tr -d ' ')"
if [ "${SPEC_COUNT}" -eq 0 ]; then
    NO_SPECS=1
    fail "No *.spec.ts anywhere under ${SRC_DIR}." \
        "The interceptor, the guard and the order ticket's validation are all" \
        "testable in a few seconds with no browser and no backend, and the" \
        "interceptor's two cases are a named criterion. A deliverable with no" \
        "unit tests is assessed as one." \
        "The runner was not started, because there is nothing for it to run."
fi

[ "${NO_SPECS}" -eq 1 ] && RUNNER="none"

case "${RUNNER}" in
    none)
        ;;
    angular)
        note "unit tests run through ${TEST_BUILDER}."
        if (cd "${SPRINT_DIR}" && npx --no-install ng test --no-watch \
                --reporters=json --output-file="${TEST_JSON}") >"${BUILD_LOG}" 2>&1; then
            TEST_OK=1
        fi
        [ -s "${TEST_JSON}" ] && REPORT_OK=1
        ;;
    jest)
        note "unit tests run through Jest."
        if (cd "${SPRINT_DIR}" && npx --no-install jest --ci --silent \
                --json --outputFile="${TEST_JSON}") >"${BUILD_LOG}" 2>&1; then
            TEST_OK=1
        fi
        [ -s "${TEST_JSON}" ] && REPORT_OK=1
        ;;
    karma)
        note "unit tests run through Karma."
        if (cd "${SPRINT_DIR}" && npx --no-install ng test --watch=false) \
                >"${BUILD_LOG}" 2>&1; then
            TEST_OK=1
        fi
        ;;
    *)
        note "no unit-test runner could be identified from angular.json or package.json."
        ;;
esac

if [ "${REPORT_OK}" -eq 1 ]; then
    TOTAL_TESTS="$(node -e '
        const report = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
        process.stdout.write(String(report.numTotalTests || 0));
    ' "${TEST_JSON}")"
    FAILED_TESTS="$(node -e '
        const report = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
        process.stdout.write(String(report.numFailedTests || 0));
    ' "${TEST_JSON}")"

    node -e '
        const report = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
        for (const file of report.testResults || []) {
            const where = file.name || file.testFilePath || "";
            for (const test of file.assertionResults || []) {
                process.stdout.write([test.status, where, test.fullName || test.title || ""].join("\t") + "\n");
            }
        }
    ' "${TEST_JSON}" >"${TEST_LIST}"

    if [ "${TEST_OK}" -eq 1 ]; then
        pass "the unit suite is green: ${TOTAL_TESTS} test(s)"
    elif [ "${TOTAL_TESTS}" -eq 0 ]; then
        fail "The runner found no tests." \
            "The interceptor, the guard and the order ticket's validation are" \
            "all testable without a browser and without your backend. A" \
            "deliverable with no unit tests is assessed as one."
    else
        fail "${FAILED_TESTS} of ${TOTAL_TESTS} unit test(s) fail." \
            "Reproduce with:" \
            "  cd ${SPRINT_DIR} && npm test" \
            "The interceptor checks below still read the report, so a named case" \
            "that is present and failing is reported as failing rather than" \
            "missing."
    fi

    lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

    SPEC_PAT="$(lower "${INTERCEPTOR_SPEC_PATTERN}")"
    ATTACH_PAT="$(lower "${INTERCEPTOR_ATTACH_TEST_PATTERN}")"
    NO_ATTACH_PAT="$(lower "${INTERCEPTOR_NO_ATTACH_TEST_PATTERN}")"

    INTERCEPTOR_TESTS="$(awk -F'\t' -v pat="${SPEC_PAT}" \
        'tolower($2) ~ pat { print }' "${TEST_LIST}" || true)"

    if [ -z "${INTERCEPTOR_TESTS}" ]; then
        fail "No spec whose path matches ${INTERCEPTOR_SPEC_PATTERN} ran any test." \
            "Criterion 2 is assessed through two named cases in the interceptor's" \
            "own spec. INTERCEPTOR_SPEC_PATTERN in manifest.env is currently" \
            "${INTERCEPTOR_SPEC_PATTERN}." \
            "If your specs are named something the pattern does not reach," \
            "correct it. If they are not written yet, this is the finding."
    else
        SPEC_FILES="$(printf '%s\n' "${INTERCEPTOR_TESTS}" | awk -F'\t' 'NF > 1 { print $2 }' \
            | LC_ALL=C sort -u | sed "s#^${SPRINT_DIR}/##" | tr '\n' ' ' || true)"
        pass "interceptor spec(s) ran: ${SPEC_FILES% }"

        check_case() {
            case_label="$1"
            case_pattern="$2"
            case_exclude="$3"
            case_key="$4"

            case_status="$(printf '%s\n' "${INTERCEPTOR_TESTS}" \
                | awk -F'\t' -v pat="${case_pattern}" -v anti="${case_exclude}" '
                    tolower($3) ~ pat { if (anti == "" || tolower($3) !~ anti) print $1 }' \
                | LC_ALL=C sort -u | tr '\n' ' ' || true)"

            case "${case_status}" in
                "")
                    fail "No interceptor test names the ${case_label} case." \
                        "The harness matched the names of the tests that ran" \
                        "against ${case_key} in manifest.env, currently" \
                        "${case_pattern}. Nothing matched." \
                        "Either the case is not written, or your test is named" \
                        "something the pattern does not reach."
                    ;;
                *failed*)
                    fail "An interceptor test for the ${case_label} case is present and failing." \
                        "That is the more useful of the two failures: the case" \
                        "exists and the interceptor does not satisfy it."
                    ;;
                *passed*)
                    pass "a test covers the ${case_label} case"
                    ;;
                *)
                    fail "The interceptor test for the ${case_label} case did not run: ${case_status}" \
                        "A skipped or todo test proves nothing."
                    ;;
            esac
        }

        check_case "attach" "${ATTACH_PAT}" "${NO_ATTACH_PAT}" "INTERCEPTOR_ATTACH_TEST_PATTERN"
        check_case "do-not-attach" "${NO_ATTACH_PAT}" "" "INTERCEPTOR_NO_ATTACH_TEST_PATTERN"

        note "a name is all this can match. Whether the do-not-attach case uses"
        note "a genuine third-party origin, rather than a path on your own API,"
        note "is read at the review."
    fi
elif [ "${RUNNER}" = "karma" ]; then
    if [ "${TEST_OK}" -eq 1 ]; then
        pass "the Karma suite is green"
    else
        printf '\n'
        tail -n 20 "${BUILD_LOG}" | sed 's/^/  | /'
        fail "The Karma suite does not pass." \
            "Reproduce with:" \
            "  cd ${SPRINT_DIR} && npm test"
    fi
    skip "the two named interceptor cases: Karma produces no machine-readable report here."
    note "the scaffold runs the Angular unit-test builder, whose json reporter"
    note "the harness reads for test names. On Karma the two cases are read at"
    note "the review instead. Say which spec covers each of them."
elif [ "${NO_SPECS}" -eq 1 ]; then
    skip "the two named interceptor cases: there is no suite to read them from."
elif [ -z "${RUNNER}" ]; then
    fail "No unit-test runner could be identified." \
        "The harness reads the test builder out of angular.json and looks for" \
        "Jest in package.json. It found neither, so it did not guess." \
        "The scaffold runs the Angular unit-test builder. Restore the test" \
        "target in angular.json, or say at the review how your suite runs."
else
    printf '\n'
    tail -n 25 "${BUILD_LOG}" | sed 's/^/  | /'
    fail "The unit suite produced no report." \
        "The output above is the tail of the run. Reproduce it with:" \
        "  cd ${SPRINT_DIR} && npm test" \
        "The harness runs the runner directly rather than through the test" \
        "script, so that it can read the JSON report and find the two named" \
        "interceptor cases. A suite that cannot start has proved nothing."
fi

# --- the error catalogue -------------------------------------------------------------------

section 'The error catalogue'

# The errorCode enumeration in each contract. The catalogue is the enum on the
# shared error envelope, so the harness reads that rather than every string in
# the file.
# shellcheck disable=SC2016  # awk program, not a shell expansion
CODE_PROGRAM='
    /errorCode:/ { look = 8; next }
    look > 0 {
        if ($0 ~ /enum:[[:space:]]*\[/) { print; look = 0 } else { look-- }
    }'

CATALOGUE=""
for contract in ${CONTRACT_FILES}; do
    contract_path="${CONTRACTS_PATH}/${contract}"
    if [ ! -f "${contract_path}" ]; then
        fail "No contract at ${CONTRACTS_DIR}/${contract}." \
            "CONTRACT_FILES in manifest.env names it. The contracts are not" \
            "yours to move."
        continue
    fi
    found="$(awk "${CODE_PROGRAM}" "${contract_path}" | grep -oE '[A-Z]+-[0-9]+' || true)"
    if [ -z "${found}" ]; then
        fail "No errorCode enumeration found in ${contract}." \
            "The harness reads the enum on the shared error envelope. If the" \
            "contract has changed shape, read it yourself and say so at the" \
            "review."
    fi
    CATALOGUE="${CATALOGUE}
${found}"
done

CATALOGUE="$(printf '%s\n' "${CATALOGUE}" | grep -E '.' | LC_ALL=C sort -u || true)"
CODE_COUNT="$(printf '%s\n' "${CATALOGUE}" | grep -c . || true)"

if [ "${CODE_COUNT}" -eq 0 ]; then
    skip "the mapping check: no error codes could be read from the contracts."
elif [ ! -e "${MAPPING_PATH}" ]; then
    fail "No error mapping at ${ERROR_MAPPING_FILE}." \
        "Criterion 6 is that every code in the catalogue renders as a message a" \
        "trader can read. The harness read ${CODE_COUNT} code(s) from the" \
        "contracts and has nothing to check them against." \
        "ERROR_MAPPING_FILE in manifest.env may name a file or a directory." \
        "Correct it if your mapping lives somewhere else." \
        "Codes in the catalogue: $(printf '%s' "${CATALOGUE}" | tr '\n' ' ')"
else
    UNMAPPED=""
    for code in ${CATALOGUE}; do
        grep -rqF "${code}" "${MAPPING_PATH}" 2>/dev/null || UNMAPPED="${UNMAPPED} ${code}"
    done

    if [ -z "${UNMAPPED}" ]; then
        pass "all ${CODE_COUNT} code(s) in the catalogue appear in ${ERROR_MAPPING_FILE}"
        note "that each code appears is all this can see. Whether the sentence"
        note "beside it means anything to a trader, and whether an unknown code"
        note "falls back to something readable rather than a blank panel, is"
        note "read at the review."
    else
        fail "Code(s) in the contracts with no rendering:${UNMAPPED}" \
            "Every one of them is a failure your API can return today. A code" \
            "that reaches the screen raw, or as a blank panel, is a finding at" \
            "the review, and the codes above are the ones it will be." \
            "The harness searched ${ERROR_MAPPING_FILE} for each code as a" \
            "literal string. A mapping that builds the code from fragments" \
            "reads as missing here, and is worth not doing anyway."
    fi
fi

# --- the bundle -------------------------------------------------------------------------------

section 'Bundle hygiene'

if [ ! -d "${DIST_PATH}" ]; then
    skip "the bundle scan: there is no build output at ${DIST_DIR}."
else
    scan_bundle() {
        scan_label="$1"
        scan_pattern="$2"
        scan_advice_1="$3"
        scan_advice_2="$4"

        scan_hits="$(grep -rliE "${scan_pattern}" "${DIST_PATH}" 2>/dev/null \
            | sed "s#^${DIST_PATH}/##" | LC_ALL=C sort | head -n 10 || true)"

        if [ -z "${scan_hits}" ]; then
            pass "no ${scan_label} in the built bundle"
        else
            fail "The built bundle matches the ${scan_label} pattern." \
                "Pattern: ${scan_pattern}" \
                "${scan_advice_1}" \
                "${scan_advice_2}" \
                "In:"
            printf '%s\n' "${scan_hits}" | sed 's/^/        /'
            printf '        %s\n' \
                "Find the line with:" \
                "  grep -rniE '${scan_pattern}' ${DIST_DIR}" \
                "A genuine false positive, a word in a message or a library" \
                "symbol, is narrowed in manifest.env and defended at the review."
        fi
    }

    scan_bundle "API key" "${BUNDLE_API_KEY_PATTERN}" \
        "The bundle is downloaded by every browser that opens the application." \
        "A key in it is a key published, and it has to be revoked, not deleted."

    scan_bundle "market-data address" "${BUNDLE_FAUXNANCE_URL_PATTERN}" \
        "This application never calls the market-data API. Prices reach the" \
        "browser through your own services, which hold the key server-side."

    scan_bundle "signing secret" "${BUNDLE_SECRET_PATTERN}" \
        "A signing secret in the bundle lets any reader mint a token every" \
        "service in the platform accepts. Nothing signs anything in a browser."

    if [ -z "${ROOT_ENV_FILE}" ]; then
        skip "the literal-value search: ROOT_ENV_FILE is empty in manifest.env."
    elif [ ! -f "${SPRINT_DIR}/${ROOT_ENV_FILE}" ]; then
        skip "the literal-value search: no ${ROOT_ENV_FILE} on this machine."
        note "that file holds the real value of your market-data key and your"
        note "signing secret. With it present the harness also searches the"
        note "bundle for those exact strings, which catches a key pasted in"
        note "under a name no pattern above would match. Copy .env.example to"
        note ".env at the repository root and this search runs."
    else
        LEAKED=""
        while IFS= read -r assignment; do
            env_name="${assignment%%=*}"
            env_value="${assignment#*=}"
            env_value="${env_value%\"}"; env_value="${env_value#\"}"
            env_value="${env_value%\'}"; env_value="${env_value#\'}"
            [ "${#env_value}" -ge 12 ] || continue
            case "${env_value}" in
                replace-with-your-fauxnance-key) continue ;;
            esac
            if grep -rqF "${env_value}" "${DIST_PATH}" 2>/dev/null; then
                LEAKED="${LEAKED} ${env_name}"
            fi
        done < <(grep -E '^[A-Z_]+=..*' "${SPRINT_DIR}/${ROOT_ENV_FILE}" 2>/dev/null || true)

        if [ -z "${LEAKED}" ]; then
            pass "no value from ${ROOT_ENV_FILE} appears in the built bundle"
        else
            fail "Value(s) from ${ROOT_ENV_FILE} appear verbatim in the built bundle:${LEAKED}" \
                "The harness names the variable and never prints the value." \
                "Treat each one as disclosed: rotate it, then find how it got" \
                "into src/. An environment file is read by a server process." \
                "Nothing in a browser bundle is private."
        fi
    fi

    note "this reads the built files as text. A value assembled at runtime from"
    note "fragments, or fetched from an endpoint of your own that hands it out,"
    note "passes here and is still a leak. Both are asked about at the review."
fi

# --- live mode ---------------------------------------------------------------------------------

if [ "${LIVE}" -eq 1 ]; then

    section 'Live: your stack'

    reachable() {
        curl -s -o /dev/null --max-time 10 "$1" 2>/dev/null
    }

    STACK_OK=1
    for target in "UI:${UI_BASE_URL}" "Trade REST API:${TRADE_API_BASE_URL}/api/v1/accounts/${DEMO_ACCOUNT_ID}" "Auth service:${AUTH_API_BASE_URL}/auth/login"; do
        label="${target%%:*}"
        url="${target#*:}"
        if reachable "${url}"; then
            pass "${label} answers at ${url}"
        else
            fail "${label} is not reachable at ${url}." \
                "Live mode starts nothing. Bring your stack up first:" \
                "  docker compose --profile platform up -d" \
                "and serve this application, then run the harness again. The" \
                "addresses come from manifest.env."
            STACK_OK=0
        fi
    done

    if [ "${STACK_OK}" -eq 0 ]; then
        skip "the three journeys and both browser probes: the stack is not up."
    else
        export E2E_BASE_URL="${UI_BASE_URL}"
        export E2E_TRADE_API="${TRADE_API_BASE_URL}"
        export E2E_AUTH_API="${AUTH_API_BASE_URL}"
        export E2E_USERNAME="${DEMO_USERNAME}"
        export E2E_PASSWORD="${DEMO_PASSWORD}"
        export E2E_ACCOUNT_ID="${DEMO_ACCOUNT_ID}"
        export E2E_SYMBOL="${DEMO_SYMBOL}"

        cooldown() {
            [ "${LOGIN_THROTTLE_COOLDOWN_SECONDS}" -gt 0 ] || return 0
            note "waiting ${LOGIN_THROTTLE_COOLDOWN_SECONDS}s for your login throttle window to clear."
            sleep "${LOGIN_THROTTLE_COOLDOWN_SECONDS}"
        }

        section 'Live: the three journeys'

        note "each journey runs on its own, in its own Playwright process. A"
        note "journey that only passes after another has run fails here."
        if [ "${LOGIN_THROTTLE_COOLDOWN_SECONDS}" -gt 0 ]; then
            note "and each waits ${LOGIN_THROTTLE_COOLDOWN_SECONDS}s first, so your login throttle does not"
            note "refuse a sign-in that this run needs."
        fi

        run_journey() {
            journey_label="$1"
            journey_spec="$2"

            if [ ! -f "${SPRINT_DIR}/${journey_spec}" ]; then
                fail "No ${journey_label} journey at ${journey_spec}." \
                    "Criterion 7 names three journeys: sign in, place an order" \
                    "and view history. manifest.env says this one lives at" \
                    "${journey_spec}. Correct it if yours is named differently."
                return
            fi

            cooldown
            journey_ok=0
            if (cd "${SPRINT_DIR}" && PLAYWRIGHT_JSON_OUTPUT_NAME="${PW_JSON}" \
                    npx --no-install playwright test "${journey_spec}" \
                    --reporter=json) >"${BUILD_LOG}" 2>&1; then
                journey_ok=1
            fi

            if [ ! -s "${PW_JSON}" ]; then
                printf '\n'
                tail -n 20 "${BUILD_LOG}" | sed 's/^/  | /'
                fail "The ${journey_label} journey produced no report." \
                    "Reproduce with:" \
                    "  cd ${SPRINT_DIR} && npx playwright test ${journey_spec}" \
                    "A suite that cannot start is usually a missing browser" \
                    "binary. Install it once with npm run e2e:install."
                return
            fi

            stats="$(node -e '
                const report = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
                const s = report.stats || {};
                process.stdout.write([s.expected || 0, s.unexpected || 0, s.flaky || 0, s.skipped || 0].join(" "));
            ' "${PW_JSON}")"
            expected="$(printf '%s' "${stats}" | cut -d' ' -f1)"
            unexpected="$(printf '%s' "${stats}" | cut -d' ' -f2)"
            flaky="$(printf '%s' "${stats}" | cut -d' ' -f3)"
            skipped="$(printf '%s' "${stats}" | cut -d' ' -f4)"

            if [ "${unexpected}" -gt 0 ]; then
                printf '\n'
                tail -n 20 "${BUILD_LOG}" | sed 's/^/  | /'
                fail "${unexpected} test(s) in the ${journey_label} journey fail." \
                    "Reproduce with:" \
                    "  cd ${SPRINT_DIR} && npx playwright test ${journey_spec}"
            elif [ "${expected}" -eq 0 ]; then
                fail "The ${journey_label} journey ran nothing: ${skipped} skipped." \
                    "The harness confirmed your stack answers before running it," \
                    "so a spec that skipped itself has decided the platform is" \
                    "absent when it is not. A skip is not a pass, and this" \
                    "journey is a named criterion."
            elif [ "${journey_ok}" -eq 1 ]; then
                pass "the ${journey_label} journey passes: ${expected} test(s), ${skipped} skipped"
                [ "${flaky}" -eq 0 ] || note "${flaky} test(s) passed only on a retry. Read them before the review."
            else
                fail "The ${journey_label} journey exited non-zero with no failing test." \
                    "That is usually a global setup or teardown, or a spec file" \
                    "that threw while loading."
            fi
        }

        run_journey "sign-in" "${E2E_LOGIN_SPEC}"
        run_journey "place-order" "${E2E_PLACE_ORDER_SPEC}"
        run_journey "view-history" "${E2E_HISTORY_SPEC}"

        section 'Live: the guard and the bearer token'

        cooldown

        cat >"${PROBE_SPEC}" <<'PROBE'
/*
 * Written by scripts/check.sh and deleted when it exits. Do not commit it, and do not
 * write your journeys against it: it drives your sign-in form through the selectors in
 * manifest.env and asserts two things no unit test can see.
 */
import { expect, test } from '@playwright/test';

const ui = process.env['HARNESS_UI'] ?? '';
const guarded = process.env['HARNESS_GUARDED_ROUTE'] ?? '/';
const login = process.env['HARNESS_LOGIN_ROUTE'] ?? '/login';
const platform = (process.env['HARNESS_PLATFORM_ORIGINS'] ?? '').split(' ').filter(Boolean);

test('an unauthenticated visit to a guarded route is redirected', async ({ page }) => {
  await page.goto(ui + guarded, { waitUntil: 'domcontentloaded' });
  await page.waitForURL((url) => url.pathname.startsWith(login), { timeout: 15_000 });
  expect(page.url()).toContain(login);
});

test('the bearer token reaches platform origins and nothing else', async ({ page }) => {
  const carried: string[] = [];
  const bare: string[] = [];

  page.on('request', (request) => {
    const header = request.headers()['authorization'] ?? '';
    const origin = new URL(request.url()).origin;
    if (!/^bearer /i.test(header)) {
      if (!bare.includes(origin)) { bare.push(origin); }
      return;
    }
    if (!carried.includes(origin)) { carried.push(origin); }
  });

  await page.goto(ui + login, { waitUntil: 'domcontentloaded' });
  await page.locator(process.env['HARNESS_USERNAME_SELECTOR'] ?? '').first()
    .fill(process.env['HARNESS_USERNAME'] ?? '');
  await page.locator(process.env['HARNESS_PASSWORD_SELECTOR'] ?? '').first()
    .fill(process.env['HARNESS_PASSWORD'] ?? '');
  await page.locator(process.env['HARNESS_SUBMIT_SELECTOR'] ?? '').first().click();
  await page.waitForURL((url) => !url.pathname.startsWith(login), { timeout: 20_000 });

  await page.goto(ui + guarded, { waitUntil: 'domcontentloaded' });
  await page.waitForTimeout(3_000);

  const foreign = carried.filter((origin) => !platform.includes(origin) && origin !== ui);
  expect(foreign, `the token was sent to ${foreign.join(', ')}`).toEqual([]);

  const reached = carried.filter((origin) => platform.includes(origin));
  expect(reached.length, 'no request to your own APIs carried a bearer token').toBeGreaterThan(0);

  const outside = bare.filter((origin) => !platform.includes(origin) && origin !== ui);
  console.log(`HARNESS_CAPTURE carried=${reached.join(',')} foreign_without_token=${outside.join(',') || 'none'}`);
});
PROBE

        HARNESS_UI="${UI_BASE_URL}" \
        HARNESS_GUARDED_ROUTE="${GUARDED_ROUTE}" \
        HARNESS_LOGIN_ROUTE="${LOGIN_ROUTE}" \
        HARNESS_PLATFORM_ORIGINS="${TRADE_API_BASE_URL} ${AUTH_API_BASE_URL}" \
        HARNESS_USERNAME="${DEMO_USERNAME}" \
        HARNESS_PASSWORD="${DEMO_PASSWORD}" \
        HARNESS_USERNAME_SELECTOR="${LOGIN_USERNAME_SELECTOR}" \
        HARNESS_PASSWORD_SELECTOR="${LOGIN_PASSWORD_SELECTOR}" \
        HARNESS_SUBMIT_SELECTOR="${LOGIN_SUBMIT_SELECTOR}" \
        PLAYWRIGHT_JSON_OUTPUT_NAME="${PW_JSON}" \
            bash -c "cd '${SPRINT_DIR}' && npx --no-install playwright test '${E2E_DIR}/zz-harness-probe.spec.ts' --workers=1 --reporter=json" \
            >"${BUILD_LOG}" 2>&1 || true

        if [ ! -s "${PW_JSON}" ]; then
            printf '\n'
            tail -n 20 "${BUILD_LOG}" | sed 's/^/  | /'
            fail "The harness probe produced no report." \
                "The probe drives your sign-in form with the selectors in" \
                "manifest.env. The output above is the tail of the run."
        else
            probe_result() {
                node -e '
                    const report = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
                    const want = process.argv[2];
                    const walk = (suite) => {
                        for (const spec of suite.specs || []) {
                            if (spec.title.includes(want)) {
                                process.stdout.write(spec.ok ? "ok" : "failed");
                                return true;
                            }
                        }
                        for (const child of suite.suites || []) { if (walk(child)) { return true; } }
                        return false;
                    };
                    for (const suite of report.suites || []) { if (walk(suite)) { break; } }
                ' "${PW_JSON}" "$1"
            }

            GUARD_RESULT="$(probe_result 'redirected')"
            CAPTURE_RESULT="$(probe_result 'nothing else')"

            case "${GUARD_RESULT}" in
                ok)
                    pass "an unauthenticated visit to ${GUARDED_ROUTE} lands on ${LOGIN_ROUTE}"
                    ;;
                *)
                    fail "An unauthenticated visit to ${GUARDED_ROUTE} was not redirected to ${LOGIN_ROUTE}." \
                        "The probe opened a fresh browser context, went straight" \
                        "to the guarded route and waited fifteen seconds for a" \
                        "navigation to the sign-in route." \
                        "A guard that renders the screen and fetches nothing" \
                        "leaves the user looking at an empty dashboard with no" \
                        "explanation. Redirect, and carry where they were going."
                    ;;
            esac

            case "${CAPTURE_RESULT}" in
                ok)
                    pass "every captured bearer went to a platform origin, and at least one did"
                    CAPTURE_LINE="$(grep -o 'HARNESS_CAPTURE .*' "${BUILD_LOG}" | head -n 1 || true)"
                    [ -z "${CAPTURE_LINE}" ] || note "${CAPTURE_LINE#HARNESS_CAPTURE }"
                    note "no third-party call may have happened during the capture."
                    note "The interceptor is still asked at the review how it"
                    note "decides, because excluding the hosts you thought of is"
                    note "not the same rule as attaching only to your own."
                    ;;
                *)
                    printf '\n'
                    tail -n 25 "${BUILD_LOG}" | sed 's/^/  | /'
                    fail "The request capture did not come out clean." \
                        "The probe signed in through your form, opened" \
                        "${GUARDED_ROUTE} and recorded every request the page" \
                        "made. It fails when a bearer token went to a host that" \
                        "is not one of yours, when no request to your own APIs" \
                        "carried one, and when the sign-in itself did not" \
                        "complete." \
                        "The output above says which. If the sign-in did not" \
                        "complete, check DEMO_USERNAME and the three selectors" \
                        "in manifest.env against your form."
                    ;;
            esac
        fi
    fi
fi

# --- result ------------------------------------------------------------------------------------

printf '\n%s\n' '----------------------------------------------------------------'
printf '%s passed, %s failed\n' "${PASSED}" "${FAILED}"

if [ "${FAILED}" -eq 0 ]; then
    if [ "${LIVE}" -eq 0 ]; then
        printf '\nThe harness is satisfied by the static checks. It has installed\n'
        printf 'your dependencies, built the production bundle, regenerated both\n'
        printf 'clients from the contracts, run your unit suite and read the built\n'
        printf 'files as text, without opening a browser. Run it again with --live\n'
        printf 'once your stack is up.\n'
    else
        printf '\nThe harness is satisfied. It has run each journey on its own, watched\n'
        printf 'a guarded route turn a signed-out visitor away, and recorded where the\n'
        printf 'bearer token went.\n'
    fi
    printf '\nAssessed by a human at the review: whether your error messages mean\n'
    printf 'anything to a trader, whether the interceptor decides by origin rather\n'
    printf 'than by a list of hosts somebody remembered, whether the blotter tells a\n'
    printf 'working order apart from a stalled one, and whether a value could reach\n'
    printf 'the browser by a route no grep can see.\n'
    exit 0
fi

printf '\nEach failure above says what was expected and where to look. The\n'
printf 'readability of your messages, the rule the interceptor actually applies\n'
printf 'and the indirect ways a secret reaches a bundle are assessed at the\n'
printf 'review, not here.\n'

exit 1
