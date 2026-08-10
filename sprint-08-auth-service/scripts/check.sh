#!/usr/bin/env bash
#
# Sprint 8 acceptance harness.
#
#   check.sh              static checks only. No container, no database, no
#                         running service.
#   check.sh --live       the static checks, then the probes against your
#                         running stack.
#   check.sh --reuse      reuse the installed node_modules instead of running
#                         npm ci again. Faster, and it stops proving that the
#                         lock file installs.
#
# Static mode installs from the lock file, builds, runs your Jest suite once and
# reads the names of the tests that ran, scans your sources for a log call that
# names a credential field, and reads your OWASP review.
#
# Live mode needs your stack up: this service running against its store, and
# your Sprint 6 service running and pointed at it. It registers a user, logs in,
# decodes the access token claim by claim, refreshes, times a wrong password
# against an unknown user, reads a stored hash back, asks your Trade REST API to
# accept a token, and fetches the OpenAPI document the service serves. What it
# does with a refresh token that has already been exchanged depends on
# ROTATION_REVOCATION in manifest.env.
#
# Both modes read your names from manifest.env, so the harness asserts your
# design rather than dictating one.
#
# Passing these checks is necessary and not sufficient. Whether a password can
# reach a log by an indirect route, whether the cost factors were chosen against
# anything, and whether the security review is a reading of your service are
# assessed at the review.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPRINT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
MANIFEST="${SPRINT_DIR}/manifest.env"

# The claims contract, from contracts/auth-api.yaml. Five are assessed. iss is
# also defined by the contract and is permitted. Anything else is a finding.
REQUIRED_CLAIMS="sub accountId roles iat exp"
PERMITTED_CLAIMS="sub accountId roles iat exp iss"

LIVE=0
REUSE=0
while [ "$#" -gt 0 ]; do
    case "$1" in
        --live) LIVE=1; shift ;;
        --reuse) REUSE=1; shift ;;
        -h|--help) sed -n '2,28p' "${BASH_SOURCE[0]}" | sed 's/^#\{1,2\} \{0,1\}//'; exit 0 ;;
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

printf 'Sprint 8 acceptance harness\n'
if [ "${LIVE}" -eq 1 ]; then
    printf 'Static checks, then live probes against your running stack.\n'
else
    printf 'Static checks only. Add --live once your stack is up.\n'
fi

# --- the manifest --------------------------------------------------------------

section 'Manifest'

[ -f "${MANIFEST}" ] || abort \
    "No manifest.env in ${SPRINT_DIR}." \
    "The harness reads your paths, your test-name patterns, your review file" \
    "and the names live mode needs from that file. If you have deleted it," \
    "restore it from the repository."

SRC_DIR=""
EXTRA_TEST_DIR=""
SERVICE_HOST=""
SERVICE_PORT=""
OPENAPI_DOCS_PATH=""
OPENAPI_JSON_PATH=""
GUARD_SPEC_PATTERN=""
GUARD_EXPIRED_TEST_PATTERN=""
GUARD_SIGNATURE_TEST_PATTERN=""
CREDENTIAL_FIELD_NAMES=""
LOG_CALL_PATTERN=""
SECURITY_REVIEW_FILE=""
SECURITY_REVIEW_TEMPLATE=""
SECURITY_REVIEW_CATEGORIES=""
SECURITY_REVIEW_NONE_MIN_WORDS=""
ROTATION_REVOCATION=""
ROTATION_DECISION_PATTERN=""
ROTATION_DECISION_MIN_WORDS=""
DEMO_USERNAME=""
DEMO_PASSWORD=""
DEMO_ACCOUNT_ID=""
UNKNOWN_USERNAME=""
WRONG_PASSWORD=""
UNIFORM_TIMING_ATTEMPTS=""
UNIFORM_TIMING_THRESHOLD_MS=""
UNIFORM_TIMING_RATIO=""
UNIFORM_TIMING_FLOOR_MS=""
THROTTLE_COOLDOWN_SECONDS=""
POSTGRES_CONTAINER=""
PG_DATABASE=""
PG_USER=""
STORED_HASH_SQL=""
TRADE_API_HOST=""
TRADE_API_PORT=""
TRADE_API_PROTECTED_PATH=""
TRADE_API_DIR=""
TRADE_API_ISSUER_CONFIG_KEYS=""
CUTOVER_BASELINE_REF=""
STUB_SECRET_EXPECTATION=""
STUB_HOST=""
STUB_PORT=""
STUB_DEV_SECRET=""

# shellcheck source=/dev/null
. "${MANIFEST}"

STATIC_KEYS="SRC_DIR GUARD_SPEC_PATTERN GUARD_EXPIRED_TEST_PATTERN
GUARD_SIGNATURE_TEST_PATTERN CREDENTIAL_FIELD_NAMES LOG_CALL_PATTERN
SECURITY_REVIEW_FILE SECURITY_REVIEW_TEMPLATE SECURITY_REVIEW_CATEGORIES
SECURITY_REVIEW_NONE_MIN_WORDS"

LIVE_KEYS="SERVICE_HOST SERVICE_PORT OPENAPI_DOCS_PATH OPENAPI_JSON_PATH
DEMO_USERNAME DEMO_PASSWORD DEMO_ACCOUNT_ID UNKNOWN_USERNAME WRONG_PASSWORD
UNIFORM_TIMING_ATTEMPTS UNIFORM_TIMING_THRESHOLD_MS UNIFORM_TIMING_RATIO
UNIFORM_TIMING_FLOOR_MS THROTTLE_COOLDOWN_SECONDS ROTATION_REVOCATION
TRADE_API_HOST TRADE_API_PORT TRADE_API_PROTECTED_PATH TRADE_API_DIR
STUB_SECRET_EXPECTATION STUB_HOST STUB_PORT"

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
        "your team decided differently and leave the rest alone. The keys" \
        "documented as optional are EXTRA_TEST_DIR, STORED_HASH_SQL," \
        "CUTOVER_BASELINE_REF and STUB_DEV_SECRET, and an empty value there" \
        "turns a probe into a skip."
fi

case "${STUB_SECRET_EXPECTATION}" in
    trusted|rejected|"") ;;
    *) abort "STUB_SECRET_EXPECTATION in manifest.env is ${STUB_SECRET_EXPECTATION}." \
        "It has to be trusted or rejected. It declares whether your platform" \
        "still uses the stub's published development secret after the cutover," \
        "and the harness asserts the decision you declared." ;;
esac

case "${ROTATION_REVOCATION}" in
    enforced|documented|"") ;;
    *) abort "ROTATION_REVOCATION in manifest.env is ${ROTATION_REVOCATION}." \
        "It has to be enforced or documented. It declares whether your service" \
        "consumes the refresh token that was presented, which is optional this" \
        "sprint, and the harness asserts the decision you declared rather than" \
        "assuming one." ;;
esac

if [ "${ROTATION_REVOCATION}" = "documented" ] && [ -z "${ROTATION_DECISION_PATTERN}" ]; then
    abort "ROTATION_REVOCATION is documented and ROTATION_DECISION_PATTERN is empty." \
        "On that setting the replay probe is replaced by a reading of your" \
        "security review, and the pattern is how the harness finds the decision" \
        "in it. Restore the default or write one that reaches your wording."
fi

for key in UNIFORM_TIMING_ATTEMPTS UNIFORM_TIMING_THRESHOLD_MS UNIFORM_TIMING_RATIO \
    UNIFORM_TIMING_FLOOR_MS SECURITY_REVIEW_NONE_MIN_WORDS ROTATION_DECISION_MIN_WORDS; do
    eval "value=\${${key}}"
    if [ -n "${value}" ]; then
        printf '%s' "${value}" | grep -qE '^[0-9]+$' || abort \
            "${key} in manifest.env is not a whole number: ${value}"
    fi
done

pass "manifest.env declares every name the harness needs"

SRC_PATH="${SPRINT_DIR}/${SRC_DIR}"
REVIEW_PATH="${SPRINT_DIR}/${SECURITY_REVIEW_FILE}"
TEMPLATE_PATH="${SPRINT_DIR}/${SECURITY_REVIEW_TEMPLATE}"

# --- files on disk ---------------------------------------------------------------

section 'Deliverables on disk'

[ -f "${SPRINT_DIR}/package.json" ] || abort \
    "No package.json in ${SPRINT_DIR}." \
    "The engineering contract for this sprint is one NestJS project rooted" \
    "here: Node 20 or later, TypeScript, and a Jest suite, where npm ci," \
    "npm run build and npm test all succeed on a machine that has never seen" \
    "your code." \
    "Write that package.json and commit it, with the lock file beside it," \
    "because every check below reads the project it describes and a teammate" \
    "cloning this repository has nothing to install without it."
pass "package.json is present"

[ -d "${SRC_PATH}" ] || abort \
    "No ${SRC_DIR} directory in ${SPRINT_DIR}." \
    "The engineering contract puts your sources under src/, or under whatever" \
    "SRC_DIR in manifest.env names, which is currently ${SRC_DIR}. Either" \
    "correct that key or put your sources there."

count_ts() {
    find "$1" -type f -name '*.ts' ! -name '*.d.ts' 2>/dev/null | wc -l | tr -d ' '
}

count_spec() {
    count_spec_dirs="$1"
    if [ -n "${EXTRA_TEST_DIR}" ] && [ -d "${SPRINT_DIR}/${EXTRA_TEST_DIR}" ]; then
        count_spec_dirs="${count_spec_dirs} ${SPRINT_DIR}/${EXTRA_TEST_DIR}"
    fi
    # shellcheck disable=SC2086  # deliberately split into one or two paths
    find ${count_spec_dirs} -type f -name '*.spec.ts' 2>/dev/null | wc -l | tr -d ' '
}

SOURCE_COUNT="$(count_ts "${SRC_PATH}")"
SPEC_COUNT="$(count_spec "${SRC_PATH}")"

if [ "${SOURCE_COUNT}" -ge 1 ]; then
    pass "${SRC_DIR} holds ${SOURCE_COUNT} TypeScript source file(s)"
else
    abort "No TypeScript source under ${SRC_DIR}." \
        "No project skeleton ships with this sprint. The engineering contract" \
        "in README.md is one NestJS project rooted here, implementing the four" \
        "operations in contracts/auth-api.yaml on port 3000, issuing HS256" \
        "access tokens with exactly the claims contract, hashing with argon2id" \
        "or bcrypt at cost 12 or above, and serving its own OpenAPI document." \
        "The controller, the guard, the token service, the hashing, the" \
        "repositories and the DTOs are yours to design from the contract and" \
        "the brief." \
        "On day one of the sprint this is the expected result. Write the entry" \
        "point and one route, then come back."
fi

if [ "${SPEC_COUNT}" -ge 1 ]; then
    pass "${SPEC_COUNT} Jest spec file(s) are present"
else
    fail "No *.spec.ts anywhere under ${SRC_DIR}${EXTRA_TEST_DIR:+ or ${EXTRA_TEST_DIR}/}." \
        "This service can be tested without a database and without an HTTP" \
        "server, and criterion 7 names two cases specifically. A deliverable" \
        "with no tests is assessed as one."
fi

if [ -f "${TEMPLATE_PATH}" ]; then
    pass "${SECURITY_REVIEW_TEMPLATE} is present"
else
    fail "No ${SECURITY_REVIEW_TEMPLATE} in ${SPRINT_DIR}." \
        "The template is the shape of the review deliverable and it ships with" \
        "this sprint folder. Restore it from the repository, or correct" \
        "SECURITY_REVIEW_TEMPLATE in manifest.env if you moved it."
fi

# --- the toolchain -----------------------------------------------------------------

section 'Toolchain'

command -v node >/dev/null 2>&1 || abort \
    "node is not on your PATH." \
    "Install Node 20 or later and try again."

command -v npm >/dev/null 2>&1 || abort \
    "npm is not on your PATH." \
    "npm ships with Node. Install Node 20 or later."

NODE_MAJOR="$(node -p 'process.versions.node.split(".")[0]' 2>/dev/null || printf '0')"
if [ "${NODE_MAJOR}" -ge 20 ]; then
    pass "node $(node -v) and npm $(npm -v) are on the PATH"
else
    abort "Node ${NODE_MAJOR} is older than the 20 the engineering contract sets." \
        "Declare it in package.json under engines.node as well, so that a" \
        "teammate on an older runtime is told rather than left guessing."
fi

if [ "${LIVE}" -eq 1 ]; then
    command -v curl >/dev/null 2>&1 || abort \
        "curl is not on your PATH, and live mode probes your API with it."
fi

# --- installing and building --------------------------------------------------------

section 'Installing and building'

BUILD_LOG="$(mktemp)"
JEST_JSON="$(mktemp)"
TEST_LIST="$(mktemp)"
RESP_BODY="$(mktemp)"
SCRATCH="$(mktemp -d)"
trap 'rm -rf "${BUILD_LOG}" "${JEST_JSON}" "${TEST_LIST}" "${RESP_BODY}" "${SCRATCH}"' EXIT

INSTALL_OK=0
if [ "${REUSE}" -eq 1 ] && [ -d "${SPRINT_DIR}/node_modules" ]; then
    skip "npm ci: --reuse was given and node_modules is present."
    note "the run that counts installs from the lock file. Drop --reuse before"
    note "you call this deliverable finished."
    INSTALL_OK=1
elif [ ! -f "${SPRINT_DIR}/package-lock.json" ]; then
    fail "No package-lock.json in ${SPRINT_DIR}." \
        "npm ci installs exactly the tree the lock file names, which is what" \
        "makes your teammate's build the build you tested. npm install writes" \
        "the file: run it once, then commit the result." \
        "The harness fell back to npm install so that the rest of the checks" \
        "could run."
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
            "reconcile them and commit both files." \
            "If argon2 fails to build, its native binding needs a compiler:" \
            "install the build tools for your platform."
    fi
fi

if [ "${INSTALL_OK}" -eq 0 ]; then
    abort "Dependencies are not installed, so nothing else could run." \
        "Fix the install reported above and run the harness again."
fi

if (cd "${SPRINT_DIR}" && npm run build) >"${BUILD_LOG}" 2>&1; then
    pass "npm run build succeeds"
else
    printf '\n'
    tail -n 25 "${BUILD_LOG}" | sed 's/^/  | /'
    fail "The build does not succeed." \
        "The output above is the tail of it. Reproduce it with:" \
        "  cd ${SPRINT_DIR} && npm run build" \
        "The build compiles ${SRC_DIR} through the TypeScript configuration you" \
        "wrote, which should exclude your specs. A service that compiles only" \
        "when the tests are included has a source file importing something from" \
        "a spec."
fi

# --- the test suite -----------------------------------------------------------------

section 'The Jest suite'

JEST_OK=0
if (cd "${SPRINT_DIR}" && npx --no-install jest --ci --silent \
        --json --outputFile="${JEST_JSON}") >"${BUILD_LOG}" 2>&1; then
    JEST_OK=1
fi

if [ ! -s "${JEST_JSON}" ]; then
    printf '\n'
    tail -n 25 "${BUILD_LOG}" | sed 's/^/  | /'
    fail "Jest produced no report." \
        "The output above is the tail of the run. Reproduce it with:" \
        "  cd ${SPRINT_DIR} && npx jest" \
        "The harness runs Jest directly rather than through the test script, so" \
        "that it can read the JSON report. If your suite runs another way," \
        "criterion 7 cannot be checked here and will be read at the review."
else
    TOTAL_TESTS="$(node -e '
        const r = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
        process.stdout.write(String(r.numTotalTests || 0));
    ' "${JEST_JSON}")"
    FAILED_TESTS="$(node -e '
        const r = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
        process.stdout.write(String(r.numFailedTests || 0));
    ' "${JEST_JSON}")"
    FAILED_SUITES="$(node -e '
        const r = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
        process.stdout.write(String(r.numFailedTestSuites || 0));
    ' "${JEST_JSON}")"

    node -e '
        const r = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
        for (const file of r.testResults || []) {
            const path = file.name || file.testFilePath || "";
            for (const test of file.assertionResults || []) {
                process.stdout.write([test.status, path, test.fullName || ""].join("\t") + "\n");
            }
        }
    ' "${JEST_JSON}" >"${TEST_LIST}"

    if [ "${JEST_OK}" -eq 1 ]; then
        pass "the Jest suite is green: ${TOTAL_TESTS} test(s)"
    elif [ "${TOTAL_TESTS}" -eq 0 ]; then
        fail "Jest ran and found no tests." \
            "Criterion 7 names two cases specifically, and this service is the" \
            "one where a defect is a breach rather than a bug. Jest picks up" \
            "*.spec.ts by the testRegex in package.json: a suite somewhere it" \
            "does not look has the same effect as no suite at all."
    elif [ "${FAILED_TESTS}" -gt 0 ]; then
        fail "${FAILED_TESTS} of ${TOTAL_TESTS} Jest test(s) fail." \
            "Reproduce with:" \
            "  cd ${SPRINT_DIR} && npx jest" \
            "The guard checks below still read the report, so a named case that" \
            "is present but failing is reported as failing rather than missing."
    else
        fail "${FAILED_SUITES} Jest suite(s) failed to run, and every test that did run passed." \
            "Reproduce with:" \
            "  cd ${SPRINT_DIR} && npx jest" \
            "A suite that cannot start is usually an import that does not" \
            "resolve, a compile error in the spec itself, or a fixture the suite" \
            "reaches for by a relative path that is right on one machine." \
            "A suite that never ran has proved nothing, which is why this is a" \
            "failure rather than a note."
    fi

    lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

    GUARD_PAT="$(lower "${GUARD_SPEC_PATTERN}")"
    EXPIRED_PAT="$(lower "${GUARD_EXPIRED_TEST_PATTERN}")"
    SIGNATURE_PAT="$(lower "${GUARD_SIGNATURE_TEST_PATTERN}")"

    GUARD_TESTS="$(awk -F'\t' -v pat="${GUARD_PAT}" \
        'tolower($2) ~ pat { print }' "${TEST_LIST}" || true)"

    GUARD_FILES="$(printf '%s\n' "${GUARD_TESTS}" | awk -F'\t' 'NF > 1 { print $2 }' \
        | LC_ALL=C sort -u | sed "s#^${SPRINT_DIR}/##" | tr '\n' ' ' || true)"

    if [ -z "${GUARD_TESTS}" ]; then
        fail "No spec file whose path matches ${GUARD_SPEC_PATTERN} ran any test." \
            "Criterion 7 is that Jest covers the guard. The harness looks for" \
            "the two named cases among the specs whose path matches" \
            "GUARD_SPEC_PATTERN in manifest.env, which is currently" \
            "${GUARD_SPEC_PATTERN}. That pattern covers the guard and whatever" \
            "the guard delegates verification to, because a guard that hands" \
            "the token to a token service is a defensible design." \
            "If your specs are named something the pattern does not reach," \
            "correct it. If they are not written yet, this is the finding."
    else
        pass "spec(s) covering the guard and its verification ran: ${GUARD_FILES% }"

        check_guard_case() {
            case_label="$1"
            case_pattern="$2"
            case_manifest_key="$3"

            case_status="$(printf '%s\n' "${GUARD_TESTS}" \
                | awk -F'\t' -v pat="${case_pattern}" \
                    'tolower($3) ~ pat { print $1 }' | LC_ALL=C sort -u | tr '\n' ' ' || true)"

            case "${case_status}" in
                "")
                    fail "No guard test names the ${case_label} path." \
                        "The harness matched the names of the tests that ran" \
                        "against ${case_manifest_key} in manifest.env, currently" \
                        "${case_pattern}. Nothing matched." \
                        "Either the case is not written, or your test is named" \
                        "something the pattern does not reach. Correct the" \
                        "pattern if it is the second."
                    ;;
                *failed*)
                    fail "A guard test for the ${case_label} path is present and failing." \
                        "That is the more useful of the two failures: the case" \
                        "exists and the guard does not satisfy it."
                    ;;
                *passed*)
                    pass "a guard test covers the ${case_label} path"
                    ;;
                *)
                    fail "The guard test for the ${case_label} path did not run: ${case_status}" \
                        "A skipped or todo test proves nothing. Criterion 7 needs" \
                        "the case to run and pass."
                    ;;
            esac
        }

        check_guard_case "expired-token" "${EXPIRED_PAT}" "GUARD_EXPIRED_TEST_PATTERN"
        check_guard_case "wrong-signature" "${SIGNATURE_PAT}" "GUARD_SIGNATURE_TEST_PATTERN"

        note "a name is all this can match. Whether the expired case builds a"
        note "genuine token with a past exp, rather than a corrupted one the"
        note "signature check refuses first, is read at the review."
    fi
fi

# --- credentials in log calls ---------------------------------------------------------

section 'The never-logged rule'

# shellcheck disable=SC2016  # awk program, not a shell expansion
BLANK_COMMENTS='
    function strip(s,   out, p) {
        out = ""
        while (length(s) > 0) {
            if (inside) {
                p = index(s, endc)
                if (p == 0) { s = "" }
                else { s = substr(s, p + length(endc)); inside = 0 }
            } else {
                p = index(s, startc)
                if (p == 0) { out = out s; s = "" }
                else { out = out substr(s, 1, p - 1); s = substr(s, p + length(startc)); inside = 1 }
            }
        }
        return out
    }
    { print NR ":" strip($0) }'

uncommented_lines() {
    sed 's://.*::' "$1" | awk -v startc='/*' -v endc='*/' "${BLANK_COMMENTS}"
}

LOG_HITS=""
SCANNED=0
while IFS= read -r file; do
    [ -n "${file}" ] || continue
    SCANNED=$((SCANNED + 1))
    rel="${file#"${SPRINT_DIR}/"}"
    while IFS= read -r numbered; do
        line="${numbered%%:*}"
        content="${numbered#*:}"
        printf '%s' "${content}" | grep -qiE "${LOG_CALL_PATTERN}" || continue
        for field in ${CREDENTIAL_FIELD_NAMES}; do
            if printf '%s' "${content}" \
                | grep -qiE "(^|[^A-Za-z0-9_])${field}([^A-Za-z0-9_]|\$)"; then
                LOG_HITS="${LOG_HITS}
        ${rel}:${line}  ${field}"
            fi
        done
    done < <(uncommented_lines "${file}")
done < <(find "${SRC_PATH}" -type f -name '*.ts' 2>/dev/null | LC_ALL=C sort)

if [ "${SCANNED}" -eq 0 ]; then
    skip "the log scan: no TypeScript sources to read."
elif [ -z "${LOG_HITS}" ]; then
    pass "no log call in ${SRC_DIR} names a credential field"
    note "this reads one line at a time, so it sees a field named in a log call"
    note "and nothing else. An error object serialised whole, a request body"
    note "handed to a logger and a stack trace carrying a DTO all reach a log"
    note "without matching anything here, and all three are asked about."
else
    fail "A log call names a credential field." \
        "The payload of a log line goes to a file, to a container log, and in a" \
        "real deployment to a system a much larger group can read than can read" \
        "your database. A password that reaches any of them is disclosed, and" \
        "deleting the line later does not recall the log." \
        "Comments are not read, so a note you wrote about not logging passwords" \
        "is not what this found. Found:"
    printf '%s\n' "${LOG_HITS#$'\n'}"
    printf '        %s\n' \
        "If one of these is a false positive, for example a redaction list" \
        "naming the keys it strips, move it out of the log call or narrow" \
        "CREDENTIAL_FIELD_NAMES in manifest.env, and be ready to defend it."
fi

# --- the security review ---------------------------------------------------------------

section 'The OWASP review'

if [ ! -f "${REVIEW_PATH}" ]; then
    fail "No ${SECURITY_REVIEW_FILE} in ${SPRINT_DIR}." \
        "Criterion 9 is a committed review. Copy the template beside it and" \
        "fill it in as you build:" \
        "  cp ${SECURITY_REVIEW_TEMPLATE} ${SECURITY_REVIEW_FILE}" \
        "If yours is named something else, say so in SECURITY_REVIEW_FILE in" \
        "manifest.env."
elif [ -f "${TEMPLATE_PATH}" ] && cmp -s "${REVIEW_PATH}" "${TEMPLATE_PATH}"; then
    fail "${SECURITY_REVIEW_FILE} is byte for byte the template." \
        "A copy of the template is a copy of the template. Every category needs" \
        "a finding and a disposition written by somebody who read this service."
else
    pass "${SECURITY_REVIEW_FILE} exists and differs from the template"

    # The first table row that starts with the category identifier and carries
    # four cells. The count is what tells the review table apart from the
    # two-column guidance table below it, which starts its rows the same way.
    review_row() {
        awk -F'|' -v cat="$1" '
            NF >= 5 && $0 ~ "^[[:space:]]*\\|[[:space:]]*" cat "([^A-Za-z0-9]|$)" {
                print
                exit
            }
        ' "${REVIEW_PATH}"
    }

    review_cell() {
        printf '%s\n' "$1" | awk -F'|' -v field="$2" '
            {
                value = $(field)
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
                print value
            }'
    }

    REVIEW_PROBLEMS=""
    for category in ${SECURITY_REVIEW_CATEGORIES}; do
        row="$(review_row "${category}")"
        if [ -z "${row}" ]; then
            REVIEW_PROBLEMS="${REVIEW_PROBLEMS}
        ${category}  no row for this category"
            continue
        fi

        finding="$(review_cell "${row}" 4)"
        disposition="$(review_cell "${row}" 5)"

        if [ -z "${finding}" ]; then
            REVIEW_PROBLEMS="${REVIEW_PROBLEMS}
        ${category}  the finding is empty"
        else
            finding_lc="$(printf '%s' "${finding}" | tr '[:upper:]' '[:lower:]')"
            case "${finding_lc}" in
                none*|"no findings"*|"n/a"*|nothing*)
                    words="$(printf '%s' "${finding}" | wc -w | tr -d ' ')"
                    if [ "${words}" -lt "${SECURITY_REVIEW_NONE_MIN_WORDS}" ]; then
                        REVIEW_PROBLEMS="${REVIEW_PROBLEMS}
        ${category}  a finding of none, with ${words} word(s) of justification"
                    fi
                    ;;
            esac
        fi

        if [ -z "${disposition}" ]; then
            REVIEW_PROBLEMS="${REVIEW_PROBLEMS}
        ${category}  the disposition is empty"
        fi
    done

    if [ -z "${REVIEW_PROBLEMS}" ]; then
        pass "every category carries a finding and a disposition"
        note "that the cells are filled is all this can see. Whether the finding"
        note "is a reading of your service, and whether the disposition"
        note "happened, is read by your instructor."
    else
        fail "The review is incomplete." \
            "Every category needs a finding and a disposition. A finding of" \
            "none needs a sentence saying what you checked and how you know," \
            "and ${SECURITY_REVIEW_NONE_MIN_WORDS} words is what counts as a sentence here. The word" \
            "on its own cannot be told apart from a category nobody looked at."
        printf '%s\n' "${REVIEW_PROBLEMS#$'\n'}"
        printf '        %s\n' \
            "The rows are read as a markdown table: category, in scope, finding," \
            "disposition. A row the harness cannot find is usually a category" \
            "identifier that has been edited, or a row split across two lines."
    fi
fi

# --- live mode -----------------------------------------------------------------------

if [ "${LIVE}" -eq 1 ]; then

    SERVICE_URL="http://${SERVICE_HOST}:${SERVICE_PORT}"
    TRADE_API_URL="http://${TRADE_API_HOST}:${TRADE_API_PORT}"
    STUB_URL="http://${STUB_HOST}:${STUB_PORT}"

    HTTP_STATUS=""
    HTTP_BODY=""
    HTTP_SECONDS=""

    request() {
        req_method="$1"
        req_url="$2"
        req_token="$3"
        req_body="$4"

        req_args=(-s -o "${RESP_BODY}" -w '%{http_code} %{time_total}' --max-time 20
            -X "${req_method}" "${req_url}")
        [ -n "${req_token}" ] && req_args+=(-H "Authorization: Bearer ${req_token}")
        if [ -n "${req_body}" ]; then
            req_args+=(-H 'Content-Type: application/json' --data "${req_body}")
        fi

        if req_result="$(curl "${req_args[@]}" 2>/dev/null)"; then
            HTTP_STATUS="${req_result%% *}"
            HTTP_SECONDS="${req_result##* }"
        else
            HTTP_STATUS="000"
            HTTP_SECONDS="0"
        fi
        HTTP_BODY="$(tr -d '\r\n' <"${RESP_BODY}")"
    }

    json_string() {
        printf '%s' "$1" | sed -n "s/.*\"$2\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -n 1
    }

    json_number() {
        printf '%s' "$1" | sed -n "s/.*\"$2\"[[:space:]]*:[[:space:]]*\(-\{0,1\}[0-9][0-9.eE+-]*\).*/\1/p" | head -n 1
    }

    top_level_keys() {
        printf '%s' "$1" | node -e '
            let raw = "";
            process.stdin.on("data", (chunk) => { raw += chunk; });
            process.stdin.on("end", () => {
                try {
                    const parsed = JSON.parse(raw);
                    if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) {
                        process.stdout.write(Object.keys(parsed).sort().join(" "));
                    }
                } catch (error) {
                    /* not JSON: the caller reports the body it got */
                }
            });
        ' 2>/dev/null || true
    }

    claim_keys() {
        printf '%s' "$1" | node -e '
            let raw = "";
            process.stdin.on("data", (chunk) => { raw += chunk; });
            process.stdin.on("end", () => {
                const parts = raw.trim().split(".");
                if (parts.length !== 3) { process.exit(3); }
                try {
                    const payload = JSON.parse(Buffer.from(parts[1], "base64url").toString("utf8"));
                    process.stdout.write(Object.keys(payload).sort().join(" "));
                } catch (error) {
                    process.exit(4);
                }
            });
        ' 2>/dev/null || true
    }

    claim_value() {
        printf '%s' "$1" | node -e '
            let raw = "";
            process.stdin.on("data", (chunk) => { raw += chunk; });
            process.stdin.on("end", () => {
                const parts = raw.trim().split(".");
                if (parts.length !== 3) { process.exit(3); }
                try {
                    const segment = process.argv[1] === "header" ? parts[0] : parts[1];
                    const decoded = JSON.parse(Buffer.from(segment, "base64url").toString("utf8"));
                    const value = decoded[process.argv[2]];
                    if (value === undefined || value === null) { process.exit(0); }
                    process.stdout.write(typeof value === "object" ? JSON.stringify(value) : String(value));
                } catch (error) {
                    process.exit(4);
                }
            });
        ' "$2" "$3" 2>/dev/null || true
    }

    # A well-formed token signed with a key the platform has never used. Every
    # part of it is right except the one part that makes it trustworthy.
    mint_token() {
        node -e '
            const crypto = require("crypto");
            const [secret, sub, accountId, issuer] = process.argv.slice(1);
            const encode = (value) => Buffer.from(JSON.stringify(value)).toString("base64url");
            const now = Math.floor(Date.now() / 1000);
            const header = encode({ alg: "HS256", typ: "JWT" });
            const payload = encode({
                sub,
                accountId: Number(accountId),
                roles: ["CUSTOMER"],
                iat: now,
                exp: now + 900,
                iss: issuer,
            });
            const signature = crypto.createHmac("sha256", secret)
                .update(header + "." + payload).digest("base64url");
            process.stdout.write(header + "." + payload + "." + signature);
        ' "$1" "$2" "$3" "$4"
    }

    expect_error() {
        label="$1"
        want_status="$2"
        want_code="$3"

        if [ "${HTTP_STATUS}" = "000" ]; then
            fail "${label}: no response from the service." \
                "It stopped answering part way through the probes."
            return
        fi

        code="$(json_string "${HTTP_BODY}" errorCode)"
        keys="$(top_level_keys "${HTTP_BODY}")"

        if [ "${code}" != "${want_code}" ]; then
            fail "${label}: expected errorCode ${want_code}, got ${code:-none}." \
                "HTTP ${HTTP_STATUS}, body: ${HTTP_BODY:-empty}" \
                "Clients branch on errorCode, so the code is the part of the" \
                "answer that has to be right."
            return
        fi

        if [ "${HTTP_STATUS}" != "${want_status}" ]; then
            fail "${label}: ${code} arrived with HTTP ${HTTP_STATUS}, and the contract pairs it with ${want_status}." \
                "Body: ${HTTP_BODY}"
            return
        fi

        if [ "${keys}" != "errorCode message" ]; then
            fail "${label}: the error body is not the platform envelope." \
                "Fields present: ${keys:-none}" \
                "The envelope is exactly errorCode and message. A field naming" \
                "which half of the credential pair was wrong is the disclosure" \
                "the contract exists to prevent, and an extra field of any kind" \
                "is a shape the Angular error handler does not read."
            return
        fi

        pass "${label}: ${code}, HTTP ${HTTP_STATUS}, in the envelope"
    }

    expect_keys() {
        label="$1"
        want_required="$2"
        want_permitted="$3"

        keys="$(top_level_keys "${HTTP_BODY}")"
        missing=""
        for field in ${want_required}; do
            case " ${keys} " in
                *" ${field} "*) ;;
                *) missing="${missing} ${field}" ;;
            esac
        done

        unexpected=""
        for field in ${keys}; do
            case " ${want_permitted} " in
                *" ${field} "*) ;;
                *) unexpected="${unexpected} ${field}" ;;
            esac
        done

        if [ -n "${missing}" ]; then
            fail "${label}: fields the contract requires are missing:${missing}" \
                "Body: ${HTTP_BODY:-empty}" \
                "The Angular client in Sprint 9 is generated from the contract," \
                "so a missing or renamed field is a compile error there."
        elif [ -n "${unexpected}" ]; then
            fail "${label}: fields the contract does not describe are present:${unexpected}" \
                "Body: ${HTTP_BODY:-empty}" \
                "Every schema in the contract sets additionalProperties: false." \
                "A field returned here is a field a consumer starts depending on."
        else
            pass "${label}: HTTP ${HTTP_STATUS} with exactly the contract's fields"
        fi
    }

    section 'Live: reaching the service'

    request GET "${SERVICE_URL}/auth/me" "" ""
    if [ "${HTTP_STATUS}" = "000" ]; then
        abort "Nothing answered at ${SERVICE_URL}." \
            "Live mode needs the service running against its store." \
            "  cd ${SPRINT_DIR} && npm run start:dev" \
            "or start it in the compose stack. If it listens elsewhere, correct" \
            "SERVICE_HOST and SERVICE_PORT in manifest.env."
    fi
    pass "the service answers at ${SERVICE_URL}"

    expect_error "GET /auth/me with no token" 401 "AUTH-401"

    section 'Live: the four endpoints'

    PROBE_SUFFIX="$(node -e 'process.stdout.write(require("crypto").randomBytes(4).toString("hex"))')"
    PROBE_USERNAME="harness-probe-${PROBE_SUFFIX}"
    PROBE_PASSWORD="$(node -e 'process.stdout.write("probe-" + require("crypto").randomBytes(12).toString("hex"))')"

    register_body() {
        printf '{"username":"%s","password":"%s","accountId":%s}' "$1" "$2" "$3"
    }

    request POST "${SERVICE_URL}/auth/register" "" \
        "$(register_body "${PROBE_USERNAME}" "${PROBE_PASSWORD}" "${DEMO_ACCOUNT_ID}")"
    if [ "${HTTP_STATUS}" = "201" ]; then
        expect_keys "POST /auth/register" "id username accountId roles" \
            "id username accountId roles createdOn"
        note "the probe registered ${PROBE_USERNAME} against account"
        note "${DEMO_ACCOUNT_ID}. Each live run leaves one more of them in your"
        note "store, which is worth a clear-down before the demonstration."
    else
        fail "POST /auth/register answered HTTP ${HTTP_STATUS} to a valid registration." \
            "Body: ${HTTP_BODY:-empty}" \
            "The contract answers 201 with a UserResponse. Registration returns" \
            "no tokens: an unauthenticated route that mints a session is an" \
            "authentication bypass waiting for its first defect." \
            "If it answered 422, DEMO_ACCOUNT_ID in manifest.env may name an" \
            "account that does not exist in your schema."
    fi

    request POST "${SERVICE_URL}/auth/register" "" \
        "$(register_body "${PROBE_USERNAME}" "${PROBE_PASSWORD}" "${DEMO_ACCOUNT_ID}")"
    expect_error "the same username registered twice" 409 "AUTH-409"

    request POST "${SERVICE_URL}/auth/register" "" \
        "$(register_body "ab" "short" "${DEMO_ACCOUNT_ID}")"
    expect_error "a registration failing field validation" 422 "VAL-422"

    LOGIN_BODY="$(printf '{"username":"%s","password":"%s"}' "${DEMO_USERNAME}" "${DEMO_PASSWORD}")"
    request POST "${SERVICE_URL}/auth/login" "" "${LOGIN_BODY}"
    if [ "${HTTP_STATUS}" != "200" ]; then
        abort "POST /auth/login did not authenticate ${DEMO_USERNAME}." \
            "HTTP ${HTTP_STATUS}, body: ${HTTP_BODY:-empty}" \
            "Everything after this needs a token. Seed the demo users, or" \
            "correct DEMO_USERNAME and DEMO_PASSWORD in manifest.env to name a" \
            "user your service can authenticate."
    fi

    expect_keys "POST /auth/login" "accessToken refreshToken tokenType expiresIn" \
        "accessToken refreshToken tokenType expiresIn"

    ACCESS_TOKEN="$(json_string "${HTTP_BODY}" accessToken)"
    REFRESH_TOKEN="$(json_string "${HTTP_BODY}" refreshToken)"
    TOKEN_TYPE="$(json_string "${HTTP_BODY}" tokenType)"
    EXPIRES_IN="$(json_number "${HTTP_BODY}" expiresIn)"

    if [ "${TOKEN_TYPE}" = "Bearer" ]; then
        pass "tokenType is Bearer"
    else
        fail "tokenType is ${TOKEN_TYPE:-absent}, and the contract fixes it as Bearer." \
            "It is a const in the schema, so a generated client compares against" \
            "the literal."
    fi

    request GET "${SERVICE_URL}/auth/me" "${ACCESS_TOKEN}" ""
    if [ "${HTTP_STATUS}" = "200" ]; then
        expect_keys "GET /auth/me with a valid token" "id username accountId roles" \
            "id username accountId roles createdOn"
        ME_USERNAME="$(json_string "${HTTP_BODY}" username)"
        if [ "${ME_USERNAME}" = "${DEMO_USERNAME}" ]; then
            pass "/auth/me names the user the token was issued to"
        else
            fail "/auth/me returned ${ME_USERNAME:-nothing} for a token issued to ${DEMO_USERNAME}." \
                "The identity comes from the verified token and from nowhere" \
                "else. Reading it from a parameter or a header the client" \
                "controls is OWASP A01."
        fi
    else
        fail "GET /auth/me answered HTTP ${HTTP_STATUS} to a token it had just issued." \
            "Body: ${HTTP_BODY:-empty}"
    fi

    section 'Live: the claims'

    ACTUAL_CLAIMS="$(claim_keys "${ACCESS_TOKEN}")"
    if [ -z "${ACTUAL_CLAIMS}" ]; then
        fail "The access token could not be decoded as a JWT." \
            "A JWT is three base64url segments joined by dots, and the middle" \
            "one is the payload. Token: ${ACCESS_TOKEN:0:24}..."
    else
        CLAIM_MISSING=""
        for claim in ${REQUIRED_CLAIMS}; do
            case " ${ACTUAL_CLAIMS} " in
                *" ${claim} "*) ;;
                *) CLAIM_MISSING="${CLAIM_MISSING} ${claim}" ;;
            esac
        done

        CLAIM_EXTRA=""
        for claim in ${ACTUAL_CLAIMS}; do
            case " ${PERMITTED_CLAIMS} " in
                *" ${claim} "*) ;;
                *) CLAIM_EXTRA="${CLAIM_EXTRA} ${claim}" ;;
            esac
        done

        if [ -n "${CLAIM_MISSING}" ]; then
            fail "The access token is missing claims the contract requires:${CLAIM_MISSING}" \
                "Claims present: ${ACTUAL_CLAIMS}" \
                "The Trade REST API reads accountId to decide which account the" \
                "caller may reach, and refuses with ACC-403 when it cannot."
        elif [ -n "${CLAIM_EXTRA}" ]; then
            fail "The access token carries claims the contract does not describe:${CLAIM_EXTRA}" \
                "Claims present: ${ACTUAL_CLAIMS}" \
                "The payload is base64 and not encryption: everything in it is" \
                "readable by anyone holding the token, and by anyone who" \
                "intercepts one. An extra claim is also a field a consumer" \
                "starts depending on, so removing it later is not a" \
                "configuration change." \
                "The contract's set is sub, accountId, roles, iat and exp, plus" \
                "iss, which it defines so that a team can tell which" \
                "implementation signed a token during the cutover."
        else
            pass "the access token carries exactly the contract's claims: ${ACTUAL_CLAIMS}"
        fi

        CLAIM_ACCOUNT="$(claim_value "${ACCESS_TOKEN}" payload accountId)"
        if [ "${CLAIM_ACCOUNT}" = "${DEMO_ACCOUNT_ID}" ]; then
            pass "accountId in the token is ${CLAIM_ACCOUNT}, matching ${DEMO_USERNAME}"
        else
            fail "accountId in the token is ${CLAIM_ACCOUNT:-absent}, and ${DEMO_USERNAME} trades account ${DEMO_ACCOUNT_ID}." \
                "Either the claim is wrong or DEMO_ACCOUNT_ID in manifest.env" \
                "names the wrong account."
        fi

        CLAIM_ROLES="$(claim_value "${ACCESS_TOKEN}" payload roles)"
        case "${CLAIM_ROLES}" in
            \[\"*\"*\]) pass "roles is a non-empty array: ${CLAIM_ROLES}" ;;
            *) fail "roles is ${CLAIM_ROLES:-absent}, and the contract types it as a non-empty array of strings." \
                "A bare string works until a consumer iterates it." ;;
        esac

        CLAIM_IAT="$(claim_value "${ACCESS_TOKEN}" payload iat)"
        CLAIM_EXP="$(claim_value "${ACCESS_TOKEN}" payload exp)"
        if [ -n "${CLAIM_IAT}" ] && [ -n "${CLAIM_EXP}" ]; then
            LIFETIME=$((CLAIM_EXP - CLAIM_IAT))
            if [ "${LIFETIME}" -eq 900 ]; then
                pass "the access token lives for ${LIFETIME} seconds, as the contract states"
            else
                fail "The access token lives for ${LIFETIME} seconds, and the contract states 900." \
                    "The lifetime is the size of the compromise in a token that" \
                    "cannot be withdrawn. A longer one is a decision to be" \
                    "defended, not a default to be left."
            fi
            if [ -n "${EXPIRES_IN}" ] && [ "${EXPIRES_IN}" != "${LIFETIME}" ]; then
                note "expiresIn in the body says ${EXPIRES_IN} and the token says"
                note "${LIFETIME}. A client that refreshes on the body's number"
                note "refreshes at the wrong moment."
            fi
        fi

        TOKEN_ALG="$(claim_value "${ACCESS_TOKEN}" header alg)"
        if [ "${TOKEN_ALG}" = "HS256" ]; then
            pass "the token header names HS256"
        else
            note "the token header names ${TOKEN_ALG:-nothing}. The contract says"
            note "HS256 in development, and RS256 with a published public key is"
            note "a documented upgrade. Anything else, and the Trade REST API"
            note "written in Sprint 6 will not verify it."
        fi
    fi

    section "Live: refresh rotation, declared ${ROTATION_REVOCATION}"

    if [ -z "${REFRESH_TOKEN}" ]; then
        skip "the rotation probes: login returned no refreshToken."
    else
        request POST "${SERVICE_URL}/auth/refresh" "" \
            "$(printf '{"refreshToken":"%s"}' "${REFRESH_TOKEN}")"
        if [ "${HTTP_STATUS}" != "200" ]; then
            fail "POST /auth/refresh answered HTTP ${HTTP_STATUS} to the refresh token login had just issued." \
                "Body: ${HTTP_BODY:-empty}" \
                "Nothing else about rotation could be probed."
        else
            expect_keys "POST /auth/refresh" "accessToken refreshToken tokenType expiresIn" \
                "accessToken refreshToken tokenType expiresIn"

            SECOND_REFRESH="$(json_string "${HTTP_BODY}" refreshToken)"

            if [ -n "${SECOND_REFRESH}" ] && [ "${SECOND_REFRESH}" != "${REFRESH_TOKEN}" ]; then
                pass "the refresh returned a different refresh token"
            else
                fail "The refresh returned the same refresh token." \
                    "Criterion 5 is that every refresh issues a new refresh" \
                    "token. Reissuing only the access token leaves a seven-day" \
                    "credential in place, and a stolen one is usable for its" \
                    "whole life without the real user noticing anything."
            fi

            # The new token is exercised before anything is replayed. On the
            # enforced setting a replay may revoke the whole chain, which would
            # take the new token with it, so the order proves both without one
            # probe destroying the other.
            request POST "${SERVICE_URL}/auth/refresh" "" \
                "$(printf '{"refreshToken":"%s"}' "${SECOND_REFRESH}")"
            THIRD_REFRESH=""
            if [ "${HTTP_STATUS}" = "200" ]; then
                pass "the refresh token the last refresh issued works"
                THIRD_REFRESH="$(json_string "${HTTP_BODY}" refreshToken)"
            else
                fail "The refresh token the last refresh issued was refused: HTTP ${HTTP_STATUS}." \
                    "Body: ${HTTP_BODY:-empty}" \
                    "A service that invalidates the old token and does not" \
                    "honour the new one logs every user out every fifteen" \
                    "minutes."
            fi

            if [ "${ROTATION_REVOCATION}" = "documented" ]; then
                skip "the replay probe: manifest.env declares ROTATION_REVOCATION=documented."
                note "on ROTATION_REVOCATION=enforced the harness would present"
                note "the refresh token that has already been exchanged and"
                note "require AUTH-401, then present the live one again to see"
                note "whether the replay revoked the rest of the chain. Neither"
                note "is probed here, because you have declared that the"
                note "presented token stays usable."
                note "What is checked instead is that the decision is written"
                note "down, because a risk nobody recorded is a risk nobody took."

                if [ ! -f "${REVIEW_PATH}" ]; then
                    fail "No ${SECURITY_REVIEW_FILE} to read the refresh decision from." \
                        "ROTATION_REVOCATION=documented moves criterion 5 into" \
                        "the security review, and there is no review to read."
                else
                    ROTATION_DECISION_LINE="$(awk \
                        -v pat="${ROTATION_DECISION_PATTERN}" \
                        -v min="${ROTATION_DECISION_MIN_WORDS}" '
                        {
                            lowered = tolower($0)
                            text = $0
                            gsub(/\|/, " ", text)
                            words = 0
                            count = split(text, parts, /[[:space:]]+/)
                            for (i = 1; i <= count; i++) {
                                if (parts[i] != "") { words++ }
                            }
                            if (lowered ~ pat && words >= min) {
                                printf "%s:  %s\n", FNR, $0
                                exit
                            }
                        }' "${REVIEW_PATH}" || true)"

                    if [ -n "${ROTATION_DECISION_LINE}" ]; then
                        pass "${SECURITY_REVIEW_FILE} records the refresh decision in writing"
                        printf '        %s\n' "${ROTATION_DECISION_LINE}"
                        note "that a line matching ${ROTATION_DECISION_PATTERN} carries"
                        note "${ROTATION_DECISION_MIN_WORDS} words or more is all this can see. Whether it"
                        note "states the residual risk, and whether the team"
                        note "accepted it deliberately, is read at the review."
                    else
                        fail "${SECURITY_REVIEW_FILE} does not record the refresh decision." \
                            "manifest.env declares ROTATION_REVOCATION=documented," \
                            "which says the refresh token that was presented stays" \
                            "usable. That is permitted this sprint and it is not" \
                            "free: two tokens that both work are two live sessions," \
                            "and if one was stolen nothing in the service can tell" \
                            "the two apart." \
                            "Write that decision and the risk it accepts in the" \
                            "review, under A04, in a line matching" \
                            "${ROTATION_DECISION_PATTERN} and at least" \
                            "${ROTATION_DECISION_MIN_WORDS} words long. Correct" \
                            "ROTATION_DECISION_PATTERN if your wording is" \
                            "something the default does not reach, or set" \
                            "ROTATION_REVOCATION=enforced if you did build the" \
                            "revocation after all."
                    fi
                fi
            else
                request POST "${SERVICE_URL}/auth/refresh" "" \
                    "$(printf '{"refreshToken":"%s"}' "${REFRESH_TOKEN}")"
                REPLAY_REFUSED=0
                if [ "${HTTP_STATUS}" = "200" ]; then
                    fail "A refresh token that has already been exchanged still works." \
                        "manifest.env declares ROTATION_REVOCATION=enforced," \
                        "which says the presented token is consumed. It is not." \
                        "Two refresh tokens that both work are two live sessions," \
                        "and if one of them was stolen the theft is now" \
                        "permanent: the thief refreshes for seven days and the" \
                        "real user notices nothing, because their own token still" \
                        "works." \
                        "Consume the presented token in the statement that reads" \
                        "it, and treat a second presentation as theft rather than" \
                        "as a retry. If your team decided not to build this, say" \
                        "so in the security review and set" \
                        "ROTATION_REVOCATION=documented."
                else
                    expect_error "the consumed refresh token presented again" 401 "AUTH-401"
                    REPLAY_REFUSED=1
                fi

                if [ "${REPLAY_REFUSED}" -eq 1 ] && [ -n "${THIRD_REFRESH}" ]; then
                    request POST "${SERVICE_URL}/auth/refresh" "" \
                        "$(printf '{"refreshToken":"%s"}' "${THIRD_REFRESH}")"
                    if [ "${HTTP_STATUS}" = "200" ]; then
                        note "the live token survived the replay, so the presented"
                        note "token was invalidated and the chain was not. The"
                        note "contract treats a second presentation as theft,"
                        note "because nothing can tell it from a repeated request,"
                        note "and revoking the chain is what ends the stolen"
                        note "session."
                    else
                        pass "the replay revoked the rest of the chain, which is the contract's theft response"
                    fi
                fi
            fi
        fi
    fi

    section 'Live: one answer for every failed login'

    if [ "${THROTTLE_COOLDOWN_SECONDS}" -gt 0 ]; then
        note "waiting ${THROTTLE_COOLDOWN_SECONDS}s for your login throttle window to empty"
        sleep "${THROTTLE_COOLDOWN_SECONDS}"
    fi

    WRONG_BODY="$(printf '{"username":"%s","password":"%s"}' "${DEMO_USERNAME}" "${WRONG_PASSWORD}")"
    UNKNOWN_BODY="$(printf '{"username":"%s","password":"%s"}' "${UNKNOWN_USERNAME}" "${WRONG_PASSWORD}")"

    request POST "${SERVICE_URL}/auth/login" "" "${WRONG_BODY}"
    WRONG_STATUS="${HTTP_STATUS}"
    WRONG_RESPONSE="${HTTP_BODY}"

    request POST "${SERVICE_URL}/auth/login" "" "${UNKNOWN_BODY}"
    UNKNOWN_STATUS="${HTTP_STATUS}"
    UNKNOWN_RESPONSE="${HTTP_BODY}"

    THROTTLED=0
    case "${WRONG_STATUS}:${UNKNOWN_STATUS}" in
        *429*) THROTTLED=1 ;;
    esac

    if [ "${THROTTLED}" -eq 1 ]; then
        skip "the uniform-failure probes: your login route answered 429."
        note "the probes before this one have already spent your throttle"
        note "allowance, so nothing measured here would mean anything. Raise"
        note "THROTTLE_COOLDOWN_SECONDS in manifest.env, or lower"
        note "UNIFORM_TIMING_ATTEMPTS, until twice the attempts plus three fit"
        note "inside the window your throttle counts over. Throttling the login"
        note "route is the right thing to have built, and it is why this probe"
        note "needs telling about it."
    elif [ "${WRONG_STATUS}" = "${UNKNOWN_STATUS}" ] && [ "${WRONG_RESPONSE}" = "${UNKNOWN_RESPONSE}" ]; then
        pass "a wrong password and an unknown user answer identically: HTTP ${WRONG_STATUS}, ${WRONG_RESPONSE}"
    else
        fail "A wrong password and an unknown user answer differently." \
            "Wrong password:  HTTP ${WRONG_STATUS}, ${WRONG_RESPONSE:-empty}" \
            "Unknown user:    HTTP ${UNKNOWN_STATUS}, ${UNKNOWN_RESPONSE:-empty}" \
            "Criterion 6. The difference is a username oracle: an attacker with" \
            "a list of addresses learns which of them are your customers" \
            "without guessing a single password, and starts the real attack" \
            "with a list that is already right."
    fi

    if [ "${THROTTLED}" -eq 0 ] && [ "${WRONG_STATUS}" != "401" ]; then
        fail "A failed login answered HTTP ${WRONG_STATUS} rather than 401." \
            "The contract answers 401 with AUTH-401 for every authentication" \
            "failure. A 404 for an unknown user is the same disclosure written" \
            "in the status line."
    fi

    timing_advice() {
        printf '        %s\n' \
            "A difference of that shape is an early return: the unknown-user" \
            "path answers as soon as the lookup misses, while the wrong-password" \
            "path spends its time verifying a hash. An attacker with a username" \
            "list and a stopwatch reads your customer base off the response" \
            "times, without guessing a single password." \
            "Make both paths do the same work. Where the username is not found," \
            "verify the supplied password against a fixed dummy hash of the same" \
            "algorithm and the same parameters, discard the result, and return" \
            "the same failure." \
            "If your machine was genuinely busy, run it again before changing" \
            "anything: this probe measures a laptop as well as a service."
    }

    median_ms() {
        LC_ALL=C sort -g | awk '{ values[NR] = $1 }
            END {
                if (NR == 0) { print "0"; exit }
                mid = int((NR + 1) / 2)
                printf "%.0f", values[mid] * 1000
            }'
    }

    # The two paths are interleaved rather than run in blocks, so that a machine
    # getting busier part way through moves both medians instead of one.
    TIMING_WRONG="${SCRATCH}/timing-wrong"
    TIMING_UNKNOWN="${SCRATCH}/timing-unknown"
    : >"${TIMING_WRONG}"
    : >"${TIMING_UNKNOWN}"

    if [ "${THROTTLED}" -eq 1 ]; then
        skip "the timing comparison: the throttle answered before it started."
    else
        attempt=1
        while [ "${attempt}" -le "${UNIFORM_TIMING_ATTEMPTS}" ]; do
            request POST "${SERVICE_URL}/auth/login" "" "${WRONG_BODY}"
            printf '%s %s\n' "${HTTP_STATUS}" "${HTTP_SECONDS}" >>"${TIMING_WRONG}"
            request POST "${SERVICE_URL}/auth/login" "" "${UNKNOWN_BODY}"
            printf '%s %s\n' "${HTTP_STATUS}" "${HTTP_SECONDS}" >>"${TIMING_UNKNOWN}"
            if [ "${THROTTLE_COOLDOWN_SECONDS}" -gt 0 ] \
                && [ "${attempt}" -lt "${UNIFORM_TIMING_ATTEMPTS}" ]; then
                sleep "${THROTTLE_COOLDOWN_SECONDS}"
            fi
            attempt=$((attempt + 1))
        done

        OFF_STATUS="$(cat "${TIMING_WRONG}" "${TIMING_UNKNOWN}" \
            | awk '$1 != "401" { print $1 }' | LC_ALL=C sort -u | tr '\n' ' ' || true)"

        WRONG_MS="$(awk '{ print $2 }' "${TIMING_WRONG}" | median_ms)"
        UNKNOWN_MS="$(awk '{ print $2 }' "${TIMING_UNKNOWN}" | median_ms)"
        DELTA_MS=$((WRONG_MS - UNKNOWN_MS))
        [ "${DELTA_MS}" -lt 0 ] && DELTA_MS=$((-DELTA_MS))

        SLOWER_MS="${WRONG_MS}"
        FASTER_MS="${UNKNOWN_MS}"
        if [ "${UNKNOWN_MS}" -gt "${WRONG_MS}" ]; then
            SLOWER_MS="${UNKNOWN_MS}"
            FASTER_MS="${WRONG_MS}"
        fi

        RATIO_EXCEEDED=0
        if [ "${DELTA_MS}" -ge "${UNIFORM_TIMING_FLOOR_MS}" ] \
            && [ "${SLOWER_MS}" -ge $((FASTER_MS * UNIFORM_TIMING_RATIO)) ]; then
            RATIO_EXCEEDED=1
        fi

        printf '  ....  %s attempt(s) each: wrong password %sms, unknown user %sms, delta %sms\n' \
            "${UNIFORM_TIMING_ATTEMPTS}" "${WRONG_MS}" "${UNKNOWN_MS}" "${DELTA_MS}"

        if [ -n "${OFF_STATUS}" ]; then
            skip "the timing comparison: some attempts answered ${OFF_STATUS% } rather than 401."
            note "a throttled request is refused before either path does any"
            note "work, so both answer in about a millisecond and the delta"
            note "above means nothing. Raise THROTTLE_COOLDOWN_SECONDS in"
            note "manifest.env, or lower UNIFORM_TIMING_ATTEMPTS, until twice"
            note "the attempts plus three fit inside the window your throttle"
            note "counts over."
        elif [ "${DELTA_MS}" -gt "${UNIFORM_TIMING_THRESHOLD_MS}" ]; then
            fail "The two paths are ${DELTA_MS}ms apart, and the threshold is ${UNIFORM_TIMING_THRESHOLD_MS}ms."
            timing_advice
        elif [ "${RATIO_EXCEEDED}" -eq 1 ]; then
            fail "One path answers in ${FASTER_MS}ms and the other in ${SLOWER_MS}ms, a factor of ${UNIFORM_TIMING_RATIO} or more apart." \
                "The absolute threshold of ${UNIFORM_TIMING_THRESHOLD_MS}ms did not catch it, and on fast" \
                "hardware it never will: a whole argon2 verification costs tens" \
                "of milliseconds there, so an early return hides comfortably" \
                "inside a threshold set for a loaded laptop. The shape of the" \
                "difference gives it away where the size of it does not."
            timing_advice
        else
            pass "the two paths are within ${UNIFORM_TIMING_THRESHOLD_MS}ms and a factor of ${UNIFORM_TIMING_RATIO} of each other"
            note "two tests, and both are deliberately forgiving. The absolute"
            note "threshold is generous because a laptop under load, a container"
            note "that has just been scheduled and a cold connection pool each"
            note "move a response by tens of milliseconds. The ratio catches the"
            note "early return on hardware fast enough that the whole hash"
            note "verification fits inside the threshold."
            note "Passing here is not proof of constant time. It is the absence"
            note "of the obvious tell."
        fi
    fi

    section 'Live: the stored password'

    if [ -z "${STORED_HASH_SQL}" ]; then
        skip "the stored-hash probe: STORED_HASH_SQL in manifest.env is empty."
        note "the store is your design, so the harness needs one statement that"
        note "returns the stored hash for ${DEMO_USERNAME}. Fill it in and the"
        note "probe runs."
    else
        STORED_HASH=""
        if [ -n "${POSTGRES_CONTAINER}" ]; then
            if command -v docker >/dev/null 2>&1; then
                STORED_HASH="$(docker exec -i "${POSTGRES_CONTAINER}" \
                    psql -U "${PG_USER}" -d "${PG_DATABASE}" -tAc "${STORED_HASH_SQL}" \
                    2>/dev/null | head -n 1 || true)"
            else
                skip "the stored-hash probe: docker is not on your PATH and POSTGRES_CONTAINER is set."
            fi
        elif command -v psql >/dev/null 2>&1; then
            STORED_HASH="$(psql -U "${PG_USER}" -d "${PG_DATABASE}" -tAc "${STORED_HASH_SQL}" \
                2>/dev/null | head -n 1 || true)"
        else
            skip "the stored-hash probe: no psql on your PATH and POSTGRES_CONTAINER is empty."
        fi

        case "${STORED_HASH}" in
            "")
                skip "the stored-hash probe: the statement returned nothing."
                note "correct STORED_HASH_SQL, PG_DATABASE, PG_USER or"
                note "POSTGRES_CONTAINER in manifest.env, or seed ${DEMO_USERNAME}."
                ;;
            \$argon2*)
                pass "the stored password is an argon2 hash"
                note "the parameters are in the value itself. Be ready to say"
                note "what you chose and what you chose it against."
                ;;
            \$2a\$*|\$2b\$*|\$2y\$*)
                COST="$(printf '%s' "${STORED_HASH}" | cut -d'$' -f3)"
                if [ "${COST:-0}" -ge 12 ] 2>/dev/null; then
                    pass "the stored password is a bcrypt hash at cost ${COST}"
                else
                    fail "The stored password is a bcrypt hash at cost ${COST}, and the contract's floor is 12." \
                        "The cost exponent is the only thing standing between a" \
                        "stolen table and a list of passwords, and each step" \
                        "doubles the work an attacker has to do."
                fi
                ;;
            *)
                fail "The stored password is not an argon2 or bcrypt value." \
                    "It starts: ${STORED_HASH:0:12}..." \
                    "Criterion 4. A general-purpose digest is built to be fast," \
                    "and fast is the one property a password hash must not have:" \
                    "a stolen table of SHA-256 digests is a stolen table of" \
                    "passwords by the weekend. Unsalted, it is worse, because one" \
                    "rainbow table serves every row." \
                    "If your store keeps the hash somewhere else, correct" \
                    "STORED_HASH_SQL in manifest.env."
                ;;
        esac
    fi

    section 'Live: the cutover'

    FORGED_SECRET="$(node -e 'process.stdout.write(require("crypto").randomBytes(32).toString("hex"))')"
    TOKEN_SUB="$(claim_value "${ACCESS_TOKEN}" payload sub)"
    FORGED_TOKEN="$(mint_token "${FORGED_SECRET}" "${TOKEN_SUB:-00000000-0000-0000-0000-000000000000}" \
        "${DEMO_ACCOUNT_ID}" "auth-service")"

    request GET "${SERVICE_URL}/auth/me" "${FORGED_TOKEN}" ""
    expect_error "GET /auth/me with a token signed by an unknown key" 401 "AUTH-401"

    request GET "${TRADE_API_URL}${TRADE_API_PROTECTED_PATH}" "${ACCESS_TOKEN}" ""
    if [ "${HTTP_STATUS}" = "000" ]; then
        skip "the Trade REST API probes: nothing answered at ${TRADE_API_URL}."
        note "criterion 3 needs your Sprint 6 service running and configured"
        note "against this one. Start it, or correct TRADE_API_HOST and"
        note "TRADE_API_PORT in manifest.env."
    else
        if [ "${HTTP_STATUS}" = "401" ]; then
            fail "The Trade REST API refused a token this service issued: HTTP 401." \
                "Body: ${HTTP_BODY:-empty}" \
                "Criterion 3. Both implementations sign HS256 with the same" \
                "JWT_SECRET and issue the same claims, so a token from either" \
                "verifies with the code written in Sprint 6 against the stub." \
                "A 401 here is one of three things: the two services hold" \
                "different secrets, that service pins an issuer and yours names" \
                "a different one, or a claim has been renamed. Decode the token" \
                "and compare it against contracts/auth-api.yaml."
        else
            pass "the Trade REST API accepted a token this service issued: HTTP ${HTTP_STATUS}"
            [ "${HTTP_STATUS}" = "403" ] && note "403 is an authorisation answer, so the token was accepted."
        fi

        request GET "${TRADE_API_URL}${TRADE_API_PROTECTED_PATH}" "${FORGED_TOKEN}" ""
        if [ "${HTTP_STATUS}" = "401" ]; then
            pass "the Trade REST API refused a token signed by an unknown key"
        else
            fail "The Trade REST API answered HTTP ${HTTP_STATUS} to a token signed with a key nobody holds." \
                "Body: ${HTTP_BODY:-empty}" \
                "Everything about that token is well formed except the" \
                "signature. Accepting it means the signature is not being" \
                "checked, or is being checked after the payload has already been" \
                "read and trusted."
        fi

        STUB_TOKEN=""
        request POST "${STUB_URL}/auth/login" "" \
            "$(printf '{"username":"%s","password":"%s"}' "${DEMO_USERNAME}" "${DEMO_PASSWORD}")"
        if [ "${HTTP_STATUS}" = "200" ]; then
            STUB_TOKEN="$(json_string "${HTTP_BODY}" accessToken)"
        elif [ -n "${STUB_DEV_SECRET}" ]; then
            STUB_TOKEN="$(mint_token "${STUB_DEV_SECRET}" \
                "${TOKEN_SUB:-00000000-0000-0000-0000-000000000000}" \
                "${DEMO_ACCOUNT_ID}" "auth-stub")"
        fi

        if [ -z "${STUB_TOKEN}" ]; then
            skip "the stub-secret probe: the stub is not running and STUB_DEV_SECRET is empty."
            note "the probe asks whether the platform still trusts the secret the"
            note "stub publishes in its own README. Start the stub, or copy that"
            note "value into STUB_DEV_SECRET in manifest.env."
        else
            request GET "${TRADE_API_URL}${TRADE_API_PROTECTED_PATH}" "${STUB_TOKEN}" ""
            STUB_STATUS="${HTTP_STATUS}"
            if [ "${STUB_SECRET_EXPECTATION}" = "rejected" ]; then
                if [ "${STUB_STATUS}" = "401" ]; then
                    pass "a token signed with the stub's secret is refused, as manifest.env declares"
                else
                    fail "A token signed with the stub's secret was answered HTTP ${STUB_STATUS}." \
                        "manifest.env declares STUB_SECRET_EXPECTATION=rejected," \
                        "which says the signing secret was rotated when the stub" \
                        "was retired. It has not been. That secret is published" \
                        "in services/auth-stub/README.md, so anybody who has read" \
                        "this repository can mint a token your platform accepts."
                fi
            else
                if [ "${STUB_STATUS}" = "401" ]; then
                    fail "A token signed with the stub's secret was refused." \
                        "manifest.env declares STUB_SECRET_EXPECTATION=trusted," \
                        "which says the platform still uses the shared" \
                        "development secret. It does not, so either the secret" \
                        "was rotated and the manifest was not updated, or the" \
                        "two services are configured with different values and" \
                        "the cutover is not the configuration change criterion 3" \
                        "asks for."
                else
                    pass "a token signed with the stub's secret is accepted, as manifest.env declares"
                    note "that is the configuration the contract describes and it"
                    note "is defensible in a training stack. The consequence is"
                    note "that the published development secret still mints"
                    note "tokens your platform trusts. Rotating it once the stub"
                    note "is gone is the better habit, and it is a line worth"
                    note "having in your security review either way."
                fi
            fi
        fi
    fi

    section 'Live: the OpenAPI document'

    request GET "${SERVICE_URL}${OPENAPI_JSON_PATH}" "" ""
    if [ "${HTTP_STATUS}" != "200" ]; then
        request GET "${SERVICE_URL}${OPENAPI_DOCS_PATH}" "" ""
        if [ "${HTTP_STATUS}" = "200" ]; then
            fail "${OPENAPI_DOCS_PATH} answers but ${OPENAPI_JSON_PATH} does not." \
                "The page is for a human. The JSON document is what a client" \
                "generator reads, and Sprint 9 generates its client rather than" \
                "writing one." \
                "Correct OPENAPI_JSON_PATH in manifest.env if yours is served" \
                "elsewhere."
        else
            fail "No OpenAPI document at ${SERVICE_URL}${OPENAPI_JSON_PATH}: HTTP ${HTTP_STATUS}." \
                "Criterion 8 is that the running service serves it. A YAML file" \
                "maintained by hand beside the code drifts from the code within" \
                "a fortnight, and the document that matters describes what is" \
                "deployed. Generate it from the decorators on your controller" \
                "and your DTOs."
        fi
    else
        DOC_MISSING=""
        for route in '/auth/register' '/auth/login' '/auth/refresh' '/auth/me'; do
            case "${HTTP_BODY}" in
                *"\"${route}\""*) ;;
                *) DOC_MISSING="${DOC_MISSING} ${route}" ;;
            esac
        done
        case "${HTTP_BODY}" in
            *'"openapi"'*) ;;
            *) DOC_MISSING="${DOC_MISSING} (no openapi version field)" ;;
        esac

        if [ -z "${DOC_MISSING}" ]; then
            pass "the service serves an OpenAPI document describing all four routes"
        else
            fail "The document at ${OPENAPI_JSON_PATH} does not describe:${DOC_MISSING}" \
                "A route missing from the generated document is a route with no" \
                "decorators on it, which means the document and the service have" \
                "already started to disagree."
        fi
    fi

    section 'Live: the no-code-change criterion'

    note "criterion 3 is that swapping the stub for this service is a"
    note "configuration change. No harness can tell a configuration change from"
    note "a code change that looks like one, so it is read at the design review."
    note "Bring this diff:"
    if [ -n "${CUTOVER_BASELINE_REF}" ]; then
        printf '        git diff %s -- %s\n' "${CUTOVER_BASELINE_REF}" "${TRADE_API_DIR}"
        if git -C "${SPRINT_DIR}" rev-parse --verify --quiet "${CUTOVER_BASELINE_REF}" >/dev/null 2>&1; then
            CHANGED="$(git -C "${SPRINT_DIR}" diff --name-only "${CUTOVER_BASELINE_REF}" \
                -- "${SPRINT_DIR}/${TRADE_API_DIR}" 2>/dev/null | wc -l | tr -d ' ' || printf '0')"
            note "${CHANGED} file(s) under ${TRADE_API_DIR} differ from ${CUTOVER_BASELINE_REF}."
            note "A changed pom.xml, application.yml or compose entry is"
            note "configuration. A changed .java file is the criterion."
        else
            note "${CUTOVER_BASELINE_REF} does not resolve in this repository."
            note "Correct CUTOVER_BASELINE_REF in manifest.env."
        fi
    else
        printf '        git diff <the commit before the cutover> -- %s\n' "${TRADE_API_DIR}"
        note "set CUTOVER_BASELINE_REF in manifest.env and the harness prints the"
        note "command with your reference in it."
    fi
    note "the configuration that should have changed: ${TRADE_API_ISSUER_CONFIG_KEYS}"
    note "and the compose entry naming which service answers on the auth port."
fi

# --- result ----------------------------------------------------------------------------

printf '\n%s\n' '----------------------------------------------------------------'
printf '%s passed, %s failed\n' "${PASSED}" "${FAILED}"

if [ "${FAILED}" -eq 0 ]; then
    if [ "${LIVE}" -eq 0 ]; then
        printf '\nThe harness is satisfied by the static checks. It has installed\n'
        printf 'your dependencies, built the service, run your tests and read your\n'
        printf 'review, and it has never issued a token. Run it again with --live\n'
        printf 'once your stack is up.\n'
    else
        printf '\nThe harness is satisfied. It has registered a user, decoded a token,\n'
        printf 'exchanged a refresh token and timed two failures, without knowing\n'
        printf 'whether a password can reach a log by a route it cannot see.\n'
    fi
    printf '\nAssessed by a human at the review: whether a credential can reach a\n'
    printf 'log indirectly, whether the cost factors were chosen against anything,\n'
    printf 'whether the refresh decision this manifest declares is one the team\n'
    printf 'reasoned about, whether the security review is a reading of your\n'
    printf 'service, and whether the cutover changed configuration and nothing else.\n'
    exit 0
fi

printf '\nEach failure above says what was expected and where to look. The\n'
printf 'indirect ways a password reaches a log, the choice of cost factors and\n'
printf 'the truth of the security review are assessed at the review, not here.\n'

exit 1
