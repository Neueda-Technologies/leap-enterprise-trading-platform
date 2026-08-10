#!/usr/bin/env bash
#
# Sprint 6 acceptance harness.
#
#   check.sh              static checks only. No container, no database, no
#                         running service, and no call to Fauxnance.
#   check.sh --live       the static checks, then the endpoint probes against
#                         your running stack.
#
# Static mode builds the service from a clean state, resolves your Sprint 5
# artefact from your local Maven repository and reads its compiled classes,
# reads your mappers for string interpolation, reads your compiled classes for
# the transaction boundary and the exception handling, reads your controller
# sources for persistence that has leaked upwards, and reads your Dockerfile.
#
# Live mode needs your stack up: your schema and seed data applied, the auth
# stub running, and your service running and reachable. It obtains a real token
# from the stub, probes the six endpoints, checks the error envelope and every
# code in the catalogue, and places several orders at once to see whether an
# update can be lost. It goes through your API and makes no assumption about
# your schema.
#
# Both modes read your names from manifest.env, so the harness asserts your
# design rather than dictating one.
#
# Passing these checks is necessary and not sufficient. Whether the transaction
# boundary is in the right place, whether every domain exception reaches the
# advice, and whether the response bodies match the contract field for field
# are assessed at the review.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPRINT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

MAIN_SRC="${SPRINT_DIR}/src/main/java"
TEST_SRC="${SPRINT_DIR}/src/test/java"
RESOURCES_DIR="${SPRINT_DIR}/src/main/resources"
CLASSES_DIR="${SPRINT_DIR}/target/classes"
MANIFEST="${SPRINT_DIR}/manifest.env"

MVN_FLAGS=(-B)

LIVE=0
while [ "$#" -gt 0 ]; do
    case "$1" in
        --live) LIVE=1; shift ;;
        -h|--help) sed -n '2,29p' "${BASH_SOURCE[0]}" | sed 's/^#\{1,2\} \{0,1\}//'; exit 0 ;;
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

printf 'Sprint 6 acceptance harness\n'
if [ "${LIVE}" -eq 1 ]; then
    printf 'Static checks, then live probes against your running stack.\n'
else
    printf 'Static checks only. Add --live once your stack is up.\n'
fi

# --- the project -------------------------------------------------------------

section 'The project'

[ -f "${SPRINT_DIR}/pom.xml" ] || abort \
    "No pom.xml in ${SPRINT_DIR}." \
    "The engineering contract for this sprint is one Maven project rooted" \
    "here: Java 21, Spring Boot 3.5.x with web and validation, MyBatis through" \
    "the Spring Boot starter, the Postgres driver, and your Sprint 5 module as" \
    "a dependency by the coordinates you gave it there." \
    "Write that pom and commit it, because every check below reads the module" \
    "it describes and a teammate cloning this repository has nothing to" \
    "compile without it."
pass "pom.xml is present"

# --- the manifest ------------------------------------------------------------

section 'Manifest'

[ -f "${MANIFEST}" ] || abort \
    "No manifest.env in ${SPRINT_DIR}." \
    "The harness reads your package names, your Sprint 5 coordinates and the" \
    "names live mode needs from that file. If you have deleted it, restore it" \
    "from the repository."

BASE_PACKAGE=""
SERVICE_HOST=""
SERVICE_PORT=""
DOMAIN_GROUP_ID=""
DOMAIN_ARTIFACT_ID=""
DOMAIN_VERSION=""
CONTROLLER_PACKAGE=""
MAPPER_PACKAGE=""
MAPPER_XML_DIR=""
ORDER_SERVICE_CLASS=""
ORDER_PLACEMENT_METHOD=""
ACCOUNT_VERSION_COLUMN=""
DOCKERFILE=""
MAPPER_SQL_INTERPOLATION_ALLOWLIST=""
AUTH_HOST=""
AUTH_PORT=""
LIVE_PASSWORD=""
LIVE_ACTIVE_USERNAME=""
LIVE_ACTIVE_ACCOUNT_ID=""
LIVE_INACTIVE_USERNAME=""
LIVE_INACTIVE_ACCOUNT_ID=""
LIVE_TRADABLE_SYMBOL=""
LIVE_UNKNOWN_SYMBOL=""
LIVE_UNKNOWN_ACCOUNT_ID=""
LIVE_CONCURRENT_ORDERS=""
LIVE_PROBE_QUANTITY=""
LIVE_PROBE_PRICE=""

# shellcheck source=/dev/null
. "${MANIFEST}"

STATIC_KEYS="BASE_PACKAGE SERVICE_HOST SERVICE_PORT DOMAIN_GROUP_ID
DOMAIN_ARTIFACT_ID DOMAIN_VERSION CONTROLLER_PACKAGE MAPPER_PACKAGE
MAPPER_XML_DIR ORDER_SERVICE_CLASS ORDER_PLACEMENT_METHOD
ACCOUNT_VERSION_COLUMN DOCKERFILE"

LIVE_KEYS="AUTH_HOST AUTH_PORT LIVE_PASSWORD LIVE_ACTIVE_USERNAME
LIVE_ACTIVE_ACCOUNT_ID LIVE_INACTIVE_USERNAME LIVE_INACTIVE_ACCOUNT_ID
LIVE_TRADABLE_SYMBOL LIVE_UNKNOWN_SYMBOL LIVE_UNKNOWN_ACCOUNT_ID
LIVE_CONCURRENT_ORDERS LIVE_PROBE_QUANTITY LIVE_PROBE_PRICE"

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
        "the file says what it is. The keys that are already filled in are" \
        "fixed by the contract or by the provided auth stub." \
        "On day one of the sprint this is the expected result: write the" \
        "application class and one endpoint, declare what you called them, and" \
        "come back."
fi

printf '%s' "${BASE_PACKAGE}" \
    | grep -qE '^[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)*$' || abort \
    "BASE_PACKAGE in manifest.env is not a Java package name: ${BASE_PACKAGE}" \
    "Write it as it appears in your package declaration, for example" \
    "  BASE_PACKAGE=com.tradingplatform.tradeapi"

for key in CONTROLLER_PACKAGE MAPPER_PACKAGE; do
    eval "value=\${${key}}"
    printf '%s' "${value}" \
        | grep -qE '^[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)*$' || abort \
        "${key} in manifest.env is not a package name: ${value}" \
        "Give it as a sub-package of BASE_PACKAGE, without the prefix. Nesting" \
        "is allowed: web.controller is as valid as web."
done

for key in ORDER_SERVICE_CLASS ORDER_PLACEMENT_METHOD; do
    eval "value=\${${key}}"
    printf '%s' "${value}" | grep -qE '^[A-Za-z_][A-Za-z0-9_]*$' || abort \
        "${key} in manifest.env is not a simple Java name: ${value}" \
        "Give the class name without its package, and the method name without" \
        "its parameters."
done

printf '%s' "${ACCOUNT_VERSION_COLUMN}" | grep -qE '^[A-Za-z_][A-Za-z0-9_]*$' || abort \
    "ACCOUNT_VERSION_COLUMN in manifest.env is not a plain identifier: ${ACCOUNT_VERSION_COLUMN}" \
    "Write the column name as it appears in your schema."

pass "manifest.env declares every name the harness needs"

BASE_PATH="${BASE_PACKAGE//.//}"
CONTROLLER_PATH="${BASE_PATH}/${CONTROLLER_PACKAGE//.//}"
CONTROLLER_FQ_PACKAGE="${BASE_PACKAGE}.${CONTROLLER_PACKAGE}"
MAPPER_FQ_PACKAGE="${BASE_PACKAGE}.${MAPPER_PACKAGE}"
DOCKERFILE_PATH="${SPRINT_DIR}/${DOCKERFILE}"

# --- files on disk -----------------------------------------------------------

section 'Deliverables on disk'

count_java() {
    find "$1" -type f -name '*.java' ! -name 'package-info.java' 2>/dev/null | wc -l | tr -d ' '
}

MAIN_SOURCES="$(count_java "${MAIN_SRC}")"
TEST_SOURCES="$(count_java "${TEST_SRC}")"

if [ "${MAIN_SOURCES}" -ge 1 ]; then
    pass "src/main/java holds ${MAIN_SOURCES} source file(s)"
else
    abort "No Java source under src/main/java." \
        "The controllers, the services, the mappers, the DTOs and the token" \
        "verification are yours to design from the contract and the brief, and" \
        "the harness reads them from the Maven source directory." \
        "On day one of the sprint this is the expected result. Write the" \
        "application class and one endpoint, then come back." \
        "A package-info.java does not count towards this number."
fi

if [ "${TEST_SOURCES}" -ge 1 ]; then
    pass "src/test/java holds ${TEST_SOURCES} source file(s)"
else
    fail "No Java source under src/test/java." \
        "This service can be tested without a container: a service test with" \
        "mocked mappers, a @WebMvcTest slice over the controllers and the" \
        "error envelope, and a mapper test against an in-memory database you" \
        "declare in test scope. A deliverable with no tests is assessed as" \
        "one."
fi

if [ -f "${DOCKERFILE_PATH}" ]; then
    pass "${DOCKERFILE} is present"
else
    fail "No ${DOCKERFILE} in ${SPRINT_DIR}." \
        "Criterion 8 is that the service builds and runs from a multi-stage" \
        "Dockerfile, written by you and living in this folder." \
        "If you named yours something else, say so in DOCKERFILE in" \
        "manifest.env."
fi

# --- the toolchain -----------------------------------------------------------

section 'Toolchain'

command -v mvn >/dev/null 2>&1 || abort \
    "mvn is not on your PATH." \
    "Install Maven 3.9 or later and try again."

command -v javap >/dev/null 2>&1 || abort \
    "javap is not on your PATH." \
    "javap ships with the JDK. Finding java but not javap usually means a" \
    "JRE is on the PATH ahead of the JDK. Install a JDK 21 or later."

command -v unzip >/dev/null 2>&1 || abort \
    "unzip is not on your PATH." \
    "The harness reads the compiled classes inside your Sprint 5 jar with it."

if [ "${LIVE}" -eq 1 ]; then
    command -v curl >/dev/null 2>&1 || abort \
        "curl is not on your PATH, and live mode probes your API with it."
fi

pass "mvn, javap and unzip are on the PATH"

# --- the build ---------------------------------------------------------------

section 'Building from a clean state'

BUILD_LOG="$(mktemp)"
CP_FILE="$(mktemp)"
JAVAP_LOG="$(mktemp)"
RESP_BODY="$(mktemp)"
CONCURRENCY_DIR="$(mktemp -d)"
trap 'rm -rf "${BUILD_LOG}" "${CP_FILE}" "${JAVAP_LOG}" "${RESP_BODY}" "${CONCURRENCY_DIR}"' EXIT

if (cd "${SPRINT_DIR}" && mvn "${MVN_FLAGS[@]}" clean verify) >"${BUILD_LOG}" 2>&1; then
    pass "mvn clean verify succeeds"
else
    printf '\n'
    tail -n 30 "${BUILD_LOG}" | sed 's/^/  | /'
    fail "The build does not succeed from a clean state." \
        "The output above is the tail of the build. Reproduce it with:" \
        "  cd ${SPRINT_DIR} && mvn clean verify" \
        "If it cannot resolve ${DOMAIN_GROUP_ID}:${DOMAIN_ARTIFACT_ID}, the" \
        "domain module has not reached your local Maven repository. There is" \
        "no aggregator build:" \
        "  cd ../sprint-05-domain-engine && mvn install"
fi

# --- the Sprint 5 artefact ---------------------------------------------------

section 'The domain module'

DOMAIN_JAR=""
if (cd "${SPRINT_DIR}" && mvn "${MVN_FLAGS[@]}" -q dependency:build-classpath \
        "-Dmdep.outputFile=${CP_FILE}" -DincludeScope=compile) >>"${BUILD_LOG}" 2>&1; then
    DOMAIN_JAR="$(tr ':' '\n' <"${CP_FILE}" | grep -F "${DOMAIN_ARTIFACT_ID}-${DOMAIN_VERSION}.jar" | head -n 1 || true)"
fi

if [ -z "${DOMAIN_JAR}" ] || [ ! -f "${DOMAIN_JAR}" ]; then
    fail "${DOMAIN_GROUP_ID}:${DOMAIN_ARTIFACT_ID}:${DOMAIN_VERSION} is not on this service's compile classpath." \
        "This service is a transport around the Sprint 5 rules, so the module" \
        "has to be a dependency of it rather than copied into it." \
        "Publish the module, then declare the same coordinates in all three" \
        "places: sprint-05-domain-engine/pom.xml, the dependency on it in" \
        "pom.xml here, and DOMAIN_* in manifest.env." \
        "  cd ../sprint-05-domain-engine && mvn install"
else
    pass "the domain module resolves from your local Maven repository"

    FORBIDDEN_IN_DOMAIN="$(unzip -p "${DOMAIN_JAR}" '*.class' 2>/dev/null \
        | LC_ALL=C grep -a -o -E 'jakarta/servlet|javax/servlet|org/springframework|org/apache/ibatis|org/mybatis' \
        | sort -u | tr '\n' ' ' || true)"
    FORBIDDEN_IN_DOMAIN="${FORBIDDEN_IN_DOMAIN% }"

    if [ -z "${FORBIDDEN_IN_DOMAIN}" ]; then
        pass "no servlet, Spring or MyBatis type is referenced by the domain classes"
    else
        fail "The domain module references types it must not know about: ${FORBIDDEN_IN_DOMAIN}" \
            "This is the second of the two violations that fail the review: an" \
            "HTTP type in the domain. The rules are called from a controller" \
            "this sprint and from a Kafka consumer in Sprint 7, and a domain" \
            "that has acquired a framework can only be used by a caller that" \
            "brought the same one." \
            "The types are in the jar at ${DOMAIN_JAR}, so republish the" \
            "module after removing them:" \
            "  cd ../sprint-05-domain-engine && mvn install"
    fi

    SQL_IN_DOMAIN="$(unzip -p "${DOMAIN_JAR}" '*.class' 2>/dev/null \
        | LC_ALL=C grep -a -c -o 'java/sql/' | head -n 1 || true)"
    if [ "${SQL_IN_DOMAIN:-0}" -gt 0 ]; then
        note "the domain classes reference java.sql types. Not a failure, and"
        note "worth a look: a domain that borrows a JDBC type has started"
        note "describing how it is stored rather than what it is."
    fi
fi

# --- the mappers -------------------------------------------------------------

section 'Mapper statements'

MAPPER_FILES=()

if [ -d "${SPRINT_DIR}/${MAPPER_XML_DIR}" ]; then
    while IFS= read -r file; do
        [ -n "${file}" ] || continue
        MAPPER_FILES[${#MAPPER_FILES[@]}]="${file}"
    done < <(find "${SPRINT_DIR}/${MAPPER_XML_DIR}" -type f -name '*.xml' 2>/dev/null | LC_ALL=C sort)
fi

# Statements written somewhere other than the declared directory, and
# statements written as annotations on the mapper interfaces.
while IFS= read -r file; do
    [ -n "${file}" ] || continue
    case " ${MAPPER_FILES[*]-} " in
        *" ${file} "*) continue ;;
    esac
    MAPPER_FILES[${#MAPPER_FILES[@]}]="${file}"
done < <(grep -rl -E '<mapper[[:space:]>]' "${RESOURCES_DIR}" --include='*.xml' 2>/dev/null | LC_ALL=C sort || true)

while IFS= read -r file; do
    [ -n "${file}" ] || continue
    MAPPER_FILES[${#MAPPER_FILES[@]}]="${file}"
done < <(grep -rl -E '@(Select|Insert|Update|Delete)(Provider)?[[:space:]]*\(' "${MAIN_SRC}" --include='*.java' 2>/dev/null | LC_ALL=C sort || true)

if [ "${#MAPPER_FILES[@]}" -eq 0 ]; then
    fail "No mapper statements found." \
        "Nothing under ${MAPPER_XML_DIR} and no @Select, @Insert, @Update or" \
        "@Delete on a Java source. The service persists through MyBatis, so" \
        "either the statements are somewhere the harness cannot see them, in" \
        "which case correct MAPPER_XML_DIR in manifest.env, or they are not" \
        "written yet."
else
    pass "${#MAPPER_FILES[@]} file(s) hold mapper statements"

    # An allowlist entry is `path-relative-to-this-folder:name`, where name is
    # what stands between the braces. The braces are left out of the manifest
    # because the shell would expand them when it reads the file.
    interpolation_allowed() {
        entry_target="$1"
        entry_token="$2"
        entry_token="${entry_token#\$\{}"
        entry_token="${entry_token%\}}"
        for entry in ${MAPPER_SQL_INTERPOLATION_ALLOWLIST}; do
            allowed_file="${entry%%:*}"
            allowed_token="${entry#*:}"
            if [ "${allowed_file}" = "${entry_target}" ] && [ "${allowed_token}" = "${entry_token}" ]; then
                return 0
            fi
        done
        return 1
    }

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

    # Numbered lines with the comment regions blanked out, so that a warning
    # somebody wrote about ${} is not reported as a use of it.
    uncommented_lines() {
        case "$1" in
            *.java) sed 's://.*::' "$1" | awk -v startc='/*' -v endc='*/' "${BLANK_COMMENTS}" ;;
            *)      awk -v startc='<!--' -v endc='-->' "${BLANK_COMMENTS}" "$1" ;;
        esac
    }

    INTERPOLATIONS=""
    ALLOWED_USED=0
    for file in "${MAPPER_FILES[@]}"; do
        rel="${file#"${SPRINT_DIR}/"}"
        while IFS= read -r numbered; do
            line="${numbered%%:*}"
            content="${numbered#*:}"
            case "${content}" in
                *"\${"*) ;;
                *) continue ;;
            esac
            while IFS= read -r token; do
                [ -n "${token}" ] || continue
                if interpolation_allowed "${rel}" "${token}"; then
                    ALLOWED_USED=$((ALLOWED_USED + 1))
                else
                    INTERPOLATIONS="${INTERPOLATIONS}
        ${rel}:${line}  ${token}"
                fi
            done < <(printf '%s\n' "${content}" | grep -o -E '\$\{[^}]*\}' 2>/dev/null || true)
        done < <(uncommented_lines "${file}")
    done

    if [ -z "${INTERPOLATIONS}" ]; then
        pass "no unapproved \${} interpolation in any mapper statement"
    else
        fail "String interpolation in a mapper statement." \
            "\${} is substituted into the statement before the driver sees it," \
            "so a value that arrives from outside the service can change what" \
            "the statement does. That is OWASP A03, injection, and in this" \
            "service the outside values include an account key, a symbol, a" \
            "status filter and two timestamps." \
            "Bind them with #{} instead, which becomes a JDBC parameter and" \
            "cannot change the shape of a statement." \
            "Comments are not read, so a warning you wrote about \${} is not" \
            "what this found. Found:"
        printf '%s\n' "${INTERPOLATIONS#$'\n'}"
        printf '        %s\n' \
            "A column name or a sort direction genuinely cannot be a bind" \
            "parameter. If that is what this is, check the value against a" \
            "fixed list of permitted names before the statement is reached," \
            "then declare it in MAPPER_SQL_INTERPOLATION_ALLOWLIST in" \
            "manifest.env, as path:name without the braces, and be ready to" \
            "defend it."
    fi

    if [ "${ALLOWED_USED}" -gt 0 ]; then
        note "${ALLOWED_USED} \${} interpolation(s) matched your allowlist. An"
        note "allowlist entry is a question you will be asked in the review:"
        note "be able to name what constrains the value."
    fi

    VERSION_IN_UPDATE=""
    VERSION_ANYWHERE=""
    for file in "${MAPPER_FILES[@]}"; do
        rel="${file#"${SPRINT_DIR}/"}"
        if grep -qE "(^|[^A-Za-z0-9_])${ACCOUNT_VERSION_COLUMN}([^A-Za-z0-9_]|$)" "${file}" 2>/dev/null; then
            VERSION_ANYWHERE="${VERSION_ANYWHERE} ${rel}"
            if grep -qiE '(^|[^A-Za-z0-9_])update([^A-Za-z0-9_]|$)' "${file}" 2>/dev/null; then
                VERSION_IN_UPDATE="${VERSION_IN_UPDATE} ${rel}"
            fi
        fi
    done

    if [ -n "${VERSION_IN_UPDATE}" ]; then
        pass "the ${ACCOUNT_VERSION_COLUMN} column appears in a mapper that updates:${VERSION_IN_UPDATE}"
        note "that the column is named is all this can see. Whether it pins the"
        note "value the row was read at, and whether zero rows affected is"
        note "treated as the refusal it is, is what live mode probes and what"
        note "the review asks about."
    elif [ -n "${VERSION_ANYWHERE}" ]; then
        fail "The ${ACCOUNT_VERSION_COLUMN} column appears in a mapper, but not in one that updates." \
            "Reading the version and not writing with it leaves the lost" \
            "update in place. The version has to be a predicate on the update," \
            "not a value checked beforehand." \
            "Seen in:${VERSION_ANYWHERE}"
    else
        fail "The ${ACCOUNT_VERSION_COLUMN} column does not appear in any mapper statement." \
            "Criterion 6 is optimistic locking on the account version column." \
            "Without it, two orders that read the same balance both write the" \
            "balance they computed, one of the two writes is lost, and nothing" \
            "reports it until somebody reconciles the cash." \
            "If your column is spelled differently, correct" \
            "ACCOUNT_VERSION_COLUMN in manifest.env."
    fi
fi

# --- the compiled service ----------------------------------------------------

section 'Transaction boundary and exception handling'

if [ ! -d "${CLASSES_DIR}/${BASE_PATH}" ]; then
    fail "Nothing compiled under ${BASE_PACKAGE}." \
        "BASE_PACKAGE in manifest.env says ${BASE_PACKAGE}, and no class" \
        "landed at target/classes/${BASE_PATH}. Either correct the manifest," \
        "move the package, or fix the build reported above." \
        "The transaction and exception handling checks need those classes and" \
        "were not run."
else
    find_class() {
        find "${CLASSES_DIR}/${BASE_PATH}" -type f -name "${1}.class" 2>/dev/null | head -n 1
    }

    fqn_of() {
        path="${1#"${CLASSES_DIR}/"}"
        path="${path%.class}"
        printf '%s' "${path//\//.}"
    }

    SERVICE_CLASS_PATH="$(find_class "${ORDER_SERVICE_CLASS}")"

    if [ -z "${SERVICE_CLASS_PATH}" ]; then
        fail "No compiled class named ${ORDER_SERVICE_CLASS} under ${BASE_PACKAGE}." \
            "manifest.env declares it as the class holding the order placement" \
            "path. Either write it, or correct ORDER_SERVICE_CLASS if you" \
            "called it something else."
    else
        SERVICE_FQN="$(fqn_of "${SERVICE_CLASS_PATH}")"
        javap -p -v -cp "${CLASSES_DIR}" "${SERVICE_FQN}" >"${JAVAP_LOG}" 2>/dev/null || true

        TRANSACTIONAL_ON="$(awk '
            /^[^ ]/            { member = "the class" }
            /^  [^ ]/          { member = $0 }
            /Transactional/    { print member }
        ' "${JAVAP_LOG}" | sed 's/^  *//' | sort -u || true)"

        if [ -z "${TRANSACTIONAL_ON}" ]; then
            fail "${SERVICE_FQN} carries no @Transactional." \
                "Criterion 5 is that order placement is transactional. An order" \
                "that is recorded while the cash movement that goes with it is" \
                "not, or the other way round, leaves the audit trail" \
                "disagreeing with the balance, and nothing in the platform" \
                "reconciles the two for you." \
                "The annotation is read from the compiled class, so one that is" \
                "commented out or imported from the wrong package is not found."
        elif printf '%s\n' "${TRANSACTIONAL_ON}" | grep -q "[^A-Za-z0-9_]${ORDER_PLACEMENT_METHOD}("; then
            pass "@Transactional is on ${ORDER_SERVICE_CLASS}.${ORDER_PLACEMENT_METHOD}"
        else
            pass "@Transactional is present on ${SERVICE_FQN}"
            note "it is not on ${ORDER_PLACEMENT_METHOD}, but on:"
            printf '%s\n' "${TRANSACTIONAL_ON}" | sed 's/^/        /'
            note "a boundary wider than the work that has to be atomic holds a"
            note "connection open for reads that did not need one. Be ready to"
            note "say why yours is where it is."
        fi
    fi

    ADVICE_HITS="$(grep -rl --include='*.class' -e 'ControllerAdvice' \
        -e 'ResponseEntityExceptionHandler' -e 'HandlerExceptionResolver' \
        "${CLASSES_DIR}" 2>/dev/null | head -n 5 || true)"

    if [ -n "${ADVICE_HITS}" ]; then
        ADVICE_NAMES=""
        while IFS= read -r hit; do
            [ -n "${hit}" ] || continue
            ADVICE_NAMES="${ADVICE_NAMES} $(basename "${hit}" .class)"
        done <<<"${ADVICE_HITS}"
        pass "centralised exception handling exists:${ADVICE_NAMES}"
        note "that it exists is all this can see. Whether every domain"
        note "exception reaches it, and leaves as its documented code and"
        note "status, is assessed at the review."
    else
        fail "No @ControllerAdvice and nothing equivalent." \
            "Criterion 4 is that one place maps every domain exception to its" \
            "documented code and status. Handling failures in each controller" \
            "produces an envelope that drifts between routes, and the Angular" \
            "client in Sprint 9 has one error handler because there is one" \
            "envelope." \
            "It also leaves the paths nobody handled to Spring's default error" \
            "response, which is not in the contract and leaks the exception" \
            "and the request path."
    fi
fi

# --- layering ----------------------------------------------------------------

section 'Layering'

if [ ! -d "${MAIN_SRC}/${CONTROLLER_PATH}" ]; then
    fail "No controller package at src/main/java/${CONTROLLER_PATH}." \
        "manifest.env says your controllers live in" \
        "${CONTROLLER_FQ_PACKAGE}. Either correct CONTROLLER_PACKAGE or move" \
        "them." \
        "The controller layering check was not run."
else
    CONTROLLER_SOURCES="$(find "${MAIN_SRC}/${CONTROLLER_PATH}" -type f -name '*.java' ! -name 'package-info.java' 2>/dev/null | wc -l | tr -d ' ')"

    BAD_IMPORTS="$(grep -rn -E "^[[:space:]]*import[[:space:]]+(static[[:space:]]+)?(${MAPPER_FQ_PACKAGE//./\\.}\.|java\.sql\.|javax\.sql\.|org\.apache\.ibatis|org\.mybatis|org\.springframework\.jdbc|jakarta\.persistence|javax\.persistence)" \
        "${MAIN_SRC}/${CONTROLLER_PATH}" --include='*.java' 2>/dev/null | sed "s#^${SPRINT_DIR}/##" || true)"

    SQL_LITERALS="$(grep -rni -E '"[^"]*(select[[:space:]]+.*[[:space:]]from[[:space:]]|insert[[:space:]]+into[[:space:]]|update[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[[:space:]]+set[[:space:]]|delete[[:space:]]+from[[:space:]])' \
        "${MAIN_SRC}/${CONTROLLER_PATH}" --include='*.java' 2>/dev/null | sed "s#^${SPRINT_DIR}/##" || true)"

    if [ "${CONTROLLER_SOURCES}" -eq 0 ]; then
        fail "No controller sources in ${CONTROLLER_FQ_PACKAGE}." \
            "Six endpoints have to be handled somewhere. If yours are in" \
            "another package, correct CONTROLLER_PACKAGE in manifest.env."
    elif [ -z "${BAD_IMPORTS}" ] && [ -z "${SQL_LITERALS}" ]; then
        pass "${CONTROLLER_SOURCES} controller source(s) import no persistence type and hold no SQL"
    else
        fail "Persistence has reached the controller layer." \
            "This is the first of the two violations that fail the review on" \
            "sight: SQL in a controller. A query written in the class that" \
            "handles the request cannot be tested without a web layer, cannot" \
            "be reused by the next caller that needs the same rows, and puts" \
            "the shape of your schema in the same file as the shape of your" \
            "JSON." \
            "A controller calls a service. The service calls the mapper."
        [ -n "${BAD_IMPORTS}" ] && printf '%s\n' "${BAD_IMPORTS}" | sed 's/^/        /'
        [ -n "${SQL_LITERALS}" ] && printf '%s\n' "${SQL_LITERALS}" | sed 's/^/        /'
    fi
fi

# --- the Dockerfile ----------------------------------------------------------

section 'Dockerfile'

if [ ! -f "${DOCKERFILE_PATH}" ]; then
    skip "no ${DOCKERFILE} to read, reported above."
else
    FROM_LINES="$(grep -nE '^[[:space:]]*[Ff][Rr][Oo][Mm][[:space:]]' "${DOCKERFILE_PATH}" || true)"
    FROM_COUNT=0
    [ -n "${FROM_LINES}" ] && FROM_COUNT="$(printf '%s\n' "${FROM_LINES}" | grep -c . || true)"

    if [ "${FROM_COUNT}" -lt 2 ]; then
        fail "${DOCKERFILE} has ${FROM_COUNT} stage(s), and a multi-stage build has more than one." \
            "One stage means the image that runs the service is the image that" \
            "built it, carrying Maven, a full JDK, the dependency cache and" \
            "your source. The reason to care is not disk: every tool in an" \
            "image is a tool available to whoever gets into the container." \
            "Build in one stage on an image carrying Maven and a JDK 21, run" \
            "from a second stage on a runtime image carrying neither, and take" \
            "the jar across with COPY --from=."
    else
        LAST_FROM_LINE="$(printf '%s\n' "${FROM_LINES}" | tail -n 1)"
        LAST_FROM_NUMBER="${LAST_FROM_LINE%%:*}"
        FINAL_IMAGE="$(printf '%s' "${LAST_FROM_LINE#*:}" | awk '{print $2}')"

        pass "${DOCKERFILE} has ${FROM_COUNT} stages"

        BUILD_IMAGE=0
        case "$(printf '%s' "${FINAL_IMAGE}" | tr '[:upper:]' '[:lower:]')" in
            *maven*|*gradle*|*jdk*|*sdk*) BUILD_IMAGE=1 ;;
        esac
        case "$(printf '%s' "${FINAL_IMAGE}" | tr '[:upper:]' '[:lower:]')" in
            *temurin*|*corretto*|*zulu*|*graalvm*|*openjdk*)
                case "${FINAL_IMAGE}" in
                    *jre*) ;;
                    *) BUILD_IMAGE=1 ;;
                esac
                ;;
        esac

        if [ "${BUILD_IMAGE}" -eq 0 ]; then
            pass "the final stage runs on ${FINAL_IMAGE}, which is not a build image"
        else
            fail "The final stage of ${DOCKERFILE} runs on ${FINAL_IMAGE}." \
                "That image carries a compiler, and a compiler in production is" \
                "a compiler in production. Two stages that both end on a JDK or" \
                "a Maven image have split the build without shrinking anything." \
                "The service needs a Java runtime to run a jar. It does not" \
                "need javac, Maven or the dependency cache."
        fi

        FINAL_STAGE_BODY="$(tail -n "+${LAST_FROM_NUMBER}" "${DOCKERFILE_PATH}")"
        if printf '%s' "${FINAL_STAGE_BODY}" | grep -qiE '^[[:space:]]*COPY[[:space:]]+--from='; then
            pass "the final stage copies its artefact from an earlier stage"
        else
            fail "The final stage of ${DOCKERFILE} has no COPY --from=." \
                "A second stage that does not take the built jar out of the" \
                "first one is either building again or shipping nothing. The" \
                "point of the split is that the artefact crosses and the" \
                "toolchain does not."
        fi

        if printf '%s' "${FINAL_STAGE_BODY}" | grep -qiE '^[[:space:]]*USER[[:space:]]'; then
            pass "the final stage sets a USER"
        else
            note "the final stage sets no USER, so the service runs as root. Not"
            note "a criterion, and it is asked about in the review. A process"
            note "that never writes to its image should not be able to."
        fi
    fi
fi

# --- live mode ---------------------------------------------------------------

if [ "${LIVE}" -eq 1 ]; then

    SERVICE_URL="http://${SERVICE_HOST}:${SERVICE_PORT}"
    AUTH_URL="http://${AUTH_HOST}:${AUTH_PORT}"

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

    json_string() {
        printf '%s' "$1" | sed -n "s/.*\"$2\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -n 1
    }

    json_number() {
        printf '%s' "$1" | sed -n "s/.*\"$2\"[[:space:]]*:[[:space:]]*\(-\{0,1\}[0-9][0-9.eE+-]*\).*/\1/p" | head -n 1
    }

    top_level_keys() {
        printf '%s' "$1" | grep -o -E '"[A-Za-z_][A-Za-z0-9_]*"[[:space:]]*:' \
            | sed 's/"//g; s/[[:space:]]*:$//' | LC_ALL=C sort -u | tr '\n' ' '
    }

    order_body() {
        printf '{"accountId":%s,"symbol":"%s","side":"BUY","quantity":%s,"price":%s,"idempotencyKey":"%s"}' \
            "$1" "$2" "$3" "$4" "$5"
    }

    new_key() {
        printf 'harness-%s-%s-%s' "$$" "$(date +%s)" "$1"
    }

    # An error response has to be the platform envelope, exactly two fields,
    # carrying one of the codes the failure is documented with.
    expect_error() {
        label="$1"
        want_status="$2"
        want_codes="$3"

        if [ "${HTTP_STATUS}" = "000" ]; then
            fail "${label}: no response from ${SERVICE_URL}." \
                "The service stopped answering part way through the probes."
            return
        fi

        code="$(json_string "${HTTP_BODY}" errorCode)"
        keys="$(top_level_keys "${HTTP_BODY}")"

        code_ok=1
        for want in ${want_codes}; do
            [ "${code}" = "${want}" ] && code_ok=0
        done

        if [ "${code_ok}" -ne 0 ]; then
            fail "${label}: expected errorCode ${want_codes// / or }, got ${code:-none}." \
                "HTTP ${HTTP_STATUS}, body: ${HTTP_BODY:-empty}" \
                "Clients branch on errorCode, so the code is the part of the" \
                "answer that has to be right."
            return
        fi

        if [ "${HTTP_STATUS}" != "${want_status}" ]; then
            fail "${label}: ${code} arrived with HTTP ${HTTP_STATUS}, and the contract pairs it with ${want_status}." \
                "Body: ${HTTP_BODY}" \
                "The code and the status are both in the catalogue and both are" \
                "assessed."
            return
        fi

        if [ "${keys}" != "errorCode message " ]; then
            fail "${label}: the error body is not the platform envelope." \
                "Fields present: ${keys:-none}" \
                "The envelope is exactly errorCode and message. Anything else" \
                "is either Spring's default error body, which leaks the" \
                "exception and the request path, or an envelope of your own," \
                "which the generated client in Sprint 9 will not read."
            return
        fi

        pass "${label}: ${code}, HTTP ${HTTP_STATUS}, in the envelope"
    }

    expect_fields() {
        label="$1"
        shift
        missing=""
        for field in "$@"; do
            case "${HTTP_BODY}" in
                *"\"${field}\""*) ;;
                *) missing="${missing} ${field}" ;;
            esac
        done
        if [ -z "${missing}" ]; then
            pass "${label}: HTTP 200 with every required field"
        else
            fail "${label}: fields the contract requires are missing:${missing}" \
                "Body: ${HTTP_BODY:-empty}" \
                "The Angular client in Sprint 9 is generated from the contract," \
                "so a missing or renamed field is a compile error there."
        fi
    }

    section 'Live: reaching the stack'

    request GET "${SERVICE_URL}/api/v1/accounts/${LIVE_ACTIVE_ACCOUNT_ID}" "" ""
    if [ "${HTTP_STATUS}" = "000" ]; then
        abort "Nothing answered at ${SERVICE_URL}." \
            "Live mode needs your stack up: your schema and seed data applied," \
            "the auth stub running, and this service running." \
            "  docker compose --profile platform up -d --build" \
            "  docker compose ps" \
            "If your service listens elsewhere, correct SERVICE_HOST and" \
            "SERVICE_PORT in manifest.env."
    fi
    pass "the service answers at ${SERVICE_URL}"

    expect_error "a protected route with no token" 401 "AUTH-401"

    LOGIN_BODY="$(printf '{"username":"%s","password":"%s"}' "${LIVE_ACTIVE_USERNAME}" "${LIVE_PASSWORD}")"
    request POST "${AUTH_URL}/auth/login" "" "${LOGIN_BODY}"
    if [ "${HTTP_STATUS}" != "200" ]; then
        abort "The auth stub at ${AUTH_URL} did not issue a token for ${LIVE_ACTIVE_USERNAME}." \
            "HTTP ${HTTP_STATUS}, body: ${HTTP_BODY:-empty}" \
            "Start it with the infrastructure:" \
            "  docker compose up -d auth-stub" \
            "The demo users and the shared password are in" \
            "services/auth-stub/README.md. Correct LIVE_ACTIVE_USERNAME and" \
            "LIVE_PASSWORD in manifest.env if you are using different ones."
    fi

    TOKEN="$(json_string "${HTTP_BODY}" accessToken)"
    if [ -z "${TOKEN}" ]; then
        abort "The auth stub answered 200 with no accessToken in the body." \
            "Body: ${HTTP_BODY}"
    fi
    pass "a token was issued for ${LIVE_ACTIVE_USERNAME}"

    # Same token, last character of the signature changed. Everything about it
    # is well formed except the one thing that makes it trustworthy.
    case "${TOKEN}" in
        *A) FORGED="${TOKEN%?}B" ;;
        *)  FORGED="${TOKEN%?}A" ;;
    esac

    request GET "${SERVICE_URL}/api/v1/accounts/${LIVE_ACTIVE_ACCOUNT_ID}" "${FORGED}" ""
    expect_error "a protected route with a tampered token" 401 "AUTH-401"

    section 'Live: the six endpoints'

    request GET "${SERVICE_URL}/api/v1/accounts/${LIVE_ACTIVE_ACCOUNT_ID}" "${TOKEN}" ""
    if [ "${HTTP_STATUS}" = "200" ]; then
        expect_fields "GET /api/v1/accounts/{id}" id accountId holderName cashBalance status version lastUpdated
    else
        fail "GET /api/v1/accounts/${LIVE_ACTIVE_ACCOUNT_ID} answered HTTP ${HTTP_STATUS} to a valid token." \
            "Body: ${HTTP_BODY:-empty}" \
            "LIVE_ACTIVE_USERNAME in manifest.env has to name a demo user whose" \
            "token reaches an account you seeded ACTIVE, and" \
            "LIVE_ACTIVE_ACCOUNT_ID has to be that account's numeric key."
    fi

    request GET "${SERVICE_URL}/api/v1/accounts/${LIVE_ACTIVE_ACCOUNT_ID}/balance" "${TOKEN}" ""
    if [ "${HTTP_STATUS}" = "200" ]; then
        expect_fields "GET /api/v1/accounts/{id}/balance" accountId cashBalance currency asOf
    else
        fail "GET /api/v1/accounts/{id}/balance answered HTTP ${HTTP_STATUS}." "Body: ${HTTP_BODY:-empty}"
    fi

    request GET "${SERVICE_URL}/api/v1/accounts/${LIVE_ACTIVE_ACCOUNT_ID}/positions" "${TOKEN}" ""
    case "${HTTP_STATUS}:${HTTP_BODY}" in
        200:\[*) pass "GET /api/v1/accounts/{id}/positions: HTTP 200 with a JSON array" ;;
        200:*)   fail "GET /api/v1/accounts/{id}/positions answered 200 with something other than an array." \
                     "Body: ${HTTP_BODY:-empty}" \
                     "The contract types this response as an array of" \
                     "PositionResponse. An object wrapping the array is a" \
                     "different type to the generated client." ;;
        *)       fail "GET /api/v1/accounts/{id}/positions answered HTTP ${HTTP_STATUS}." "Body: ${HTTP_BODY:-empty}" ;;
    esac

    request GET "${SERVICE_URL}/api/v1/accounts/${LIVE_ACTIVE_ACCOUNT_ID}/orders" "${TOKEN}" ""
    case "${HTTP_STATUS}:${HTTP_BODY}" in
        200:\[*) pass "GET /api/v1/accounts/{id}/orders: HTTP 200 with a JSON array" ;;
        200:*)   fail "GET /api/v1/accounts/{id}/orders answered 200 with something other than an array." \
                     "Body: ${HTTP_BODY:-empty}" ;;
        *)       fail "GET /api/v1/accounts/{id}/orders answered HTTP ${HTTP_STATUS}." "Body: ${HTTP_BODY:-empty}" ;;
    esac

    PLACED_KEY="$(new_key place)"
    request POST "${SERVICE_URL}/api/v1/orders" "${TOKEN}" \
        "$(order_body "${LIVE_ACTIVE_ACCOUNT_ID}" "${LIVE_TRADABLE_SYMBOL}" "${LIVE_PROBE_QUANTITY}" "${LIVE_PROBE_PRICE}" "${PLACED_KEY}")"

    PLACED_ID=""
    PLACED_STATUS=""
    if [ "${HTTP_STATUS}" = "200" ]; then
        expect_fields "POST /api/v1/orders" orderId status message symbol side quantity price
        PLACED_ID="$(json_string "${HTTP_BODY}" orderId)"
        PLACED_STATUS="$(json_string "${HTTP_BODY}" status)"
    else
        fail "POST /api/v1/orders answered HTTP ${HTTP_STATUS} to an affordable order." \
            "Body: ${HTTP_BODY:-empty}" \
            "The probe buys ${LIVE_PROBE_QUANTITY} unit(s) of" \
            "${LIVE_TRADABLE_SYMBOL} at ${LIVE_PROBE_PRICE}. If that symbol is" \
            "not in your instruments table, or is not tradable, correct" \
            "LIVE_TRADABLE_SYMBOL in manifest.env." \
            "Everything after this depends on an order having been placed."
    fi

    if [ -n "${PLACED_ID}" ]; then
        CANCEL_ID="${PLACED_ID#ORD-}"
        request DELETE "${SERVICE_URL}/api/v1/orders/${CANCEL_ID}" "${TOKEN}" ""
        case "${HTTP_STATUS}" in
            200)
                expect_fields "DELETE /api/v1/orders/{id}" orderId status message symbol side quantity price
                ;;
            409)
                expect_error "DELETE /api/v1/orders/{id} on an order already resolved" 409 "ORD-409"
                note "the order came back ${PLACED_STATUS:-unknown} from placement,"
                note "so it was never cancellable. That is the Sprint 6 shape:"
                note "the endpoint answered, and the cancellation path itself is"
                note "walked at the review."
                ;;
            *)
                fail "DELETE /api/v1/orders/{id} answered HTTP ${HTTP_STATUS}." \
                    "Body: ${HTTP_BODY:-empty}" \
                    "The contract allows 200 for a working order and 409 with" \
                    "ORD-409 for one that has already reached a terminal state." \
                    "The identifier in the path is the UUID without the ORD-" \
                    "display prefix."
                ;;
        esac
    else
        skip "DELETE /api/v1/orders/{id}: no order was placed to cancel."
    fi

    section 'Live: the error catalogue'

    request POST "${SERVICE_URL}/api/v1/orders" "${TOKEN}" \
        "$(order_body "${LIVE_ACTIVE_ACCOUNT_ID}" "${LIVE_TRADABLE_SYMBOL}" "${LIVE_PROBE_QUANTITY}" "${LIVE_PROBE_PRICE}" "${PLACED_KEY}")"
    expect_error "the same idempotency key twice" 409 "ORD-409"

    request POST "${SERVICE_URL}/api/v1/orders" "${TOKEN}" \
        "$(order_body "${LIVE_ACTIVE_ACCOUNT_ID}" "${LIVE_TRADABLE_SYMBOL}" 0 "${LIVE_PROBE_PRICE}" "$(new_key invalid)")"
    expect_error "an order with a quantity of zero" 422 "VAL-422"

    request POST "${SERVICE_URL}/api/v1/orders" "${TOKEN}" \
        "$(order_body "${LIVE_ACTIVE_ACCOUNT_ID}" "${LIVE_UNKNOWN_SYMBOL}" "${LIVE_PROBE_QUANTITY}" "${LIVE_PROBE_PRICE}" "$(new_key unknownsym)")"
    expect_error "an order in an instrument that does not exist" 404 "INS-404"

    request POST "${SERVICE_URL}/api/v1/orders" "${TOKEN}" \
        "$(order_body "${LIVE_ACTIVE_ACCOUNT_ID}" "${LIVE_TRADABLE_SYMBOL}" 1000000 9999.99 "$(new_key funds)")"
    expect_error "a buy costing more than the account holds" 400 "ORD-400"

    request GET "${SERVICE_URL}/api/v1/accounts/${LIVE_UNKNOWN_ACCOUNT_ID}" "${TOKEN}" ""
    UNKNOWN_CODE="$(json_string "${HTTP_BODY}" errorCode)"
    if [ "${UNKNOWN_CODE}" = "ACC-403" ]; then
        expect_error "an account key that does not exist" 403 "ACC-403"
        note "ACC-403 rather than ACC-404, because the token does not grant that"
        note "account and the service refused before it looked. Both are"
        note "defensible and this one gives away less: answering 404 for keys"
        note "that do not exist and 403 for keys that do lets a caller"
        note "enumerate your accounts. Be ready to say which you chose."
    else
        expect_error "an account key that does not exist" 404 "ACC-404"
    fi

    INACTIVE_LOGIN="$(printf '{"username":"%s","password":"%s"}' "${LIVE_INACTIVE_USERNAME}" "${LIVE_PASSWORD}")"
    request POST "${AUTH_URL}/auth/login" "" "${INACTIVE_LOGIN}"
    INACTIVE_TOKEN="$(json_string "${HTTP_BODY}" accessToken)"
    if [ -z "${INACTIVE_TOKEN}" ]; then
        skip "the inactive-account probe: the stub issued no token for ${LIVE_INACTIVE_USERNAME}."
    else
        request POST "${SERVICE_URL}/api/v1/orders" "${INACTIVE_TOKEN}" \
            "$(order_body "${LIVE_INACTIVE_ACCOUNT_ID}" "${LIVE_TRADABLE_SYMBOL}" "${LIVE_PROBE_QUANTITY}" "${LIVE_PROBE_PRICE}" "$(new_key inactive)")"
        INACTIVE_CODE="$(json_string "${HTTP_BODY}" errorCode)"
        if [ "${INACTIVE_CODE}" = "ACC-403" ]; then
            expect_error "an order from an account that is not ACTIVE" 403 "ACC-403"
        else
            fail "An order from ${LIVE_INACTIVE_USERNAME} on account ${LIVE_INACTIVE_ACCOUNT_ID} was answered ${INACTIVE_CODE:-with no code}, HTTP ${HTTP_STATUS}." \
                "Body: ${HTTP_BODY:-empty}" \
                "Business rule 2 refuses an account that is not ACTIVE, before" \
                "the instrument, the cash and the idempotency key are looked" \
                "at, and the code is ACC-403." \
                "If the account behind that demo user is ACTIVE in your seed" \
                "data, this probe is pointed at the wrong one: correct" \
                "LIVE_INACTIVE_USERNAME and LIVE_INACTIVE_ACCOUNT_ID in" \
                "manifest.env."
        fi
    fi

    section 'Live: two customers spending the same money'

    request GET "${SERVICE_URL}/api/v1/accounts/${LIVE_ACTIVE_ACCOUNT_ID}/balance" "${TOKEN}" ""
    BALANCE_BEFORE="$(json_number "${HTTP_BODY}" cashBalance)"

    if [ -z "${BALANCE_BEFORE}" ]; then
        skip "the concurrency probe: the balance endpoint returned no cashBalance to compare against."
    else
        i=1
        while [ "${i}" -le "${LIVE_CONCURRENT_ORDERS}" ]; do
            (
                body="$(order_body "${LIVE_ACTIVE_ACCOUNT_ID}" "${LIVE_TRADABLE_SYMBOL}" \
                    "${LIVE_PROBE_QUANTITY}" "${LIVE_PROBE_PRICE}" "$(new_key "concurrent-${i}")")"
                status="$(curl -s -o "${CONCURRENCY_DIR}/body-${i}" -w '%{http_code}' --max-time 20 \
                    -X POST "${SERVICE_URL}/api/v1/orders" \
                    -H "Authorization: Bearer ${TOKEN}" \
                    -H 'Content-Type: application/json' \
                    --data "${body}" 2>/dev/null || printf '000')"
                printf '%s' "${status}" >"${CONCURRENCY_DIR}/status-${i}"
            ) &
            i=$((i + 1))
        done
        wait

        ACCEPTED=0
        REJECTED=0
        TERMINAL=0
        WORKING=0
        OTHER=0
        i=1
        while [ "${i}" -le "${LIVE_CONCURRENT_ORDERS}" ]; do
            status="$(cat "${CONCURRENCY_DIR}/status-${i}" 2>/dev/null || printf '000')"
            body="$(tr -d '\r\n' <"${CONCURRENCY_DIR}/body-${i}" 2>/dev/null || printf '')"
            order_status="$(json_string "${body}" status)"
            case "${status}" in
                200)
                    ACCEPTED=$((ACCEPTED + 1))
                    case "${order_status}" in
                        NEW) WORKING=$((WORKING + 1)) ;;
                        *)   TERMINAL=$((TERMINAL + 1)) ;;
                    esac
                    ;;
                409) REJECTED=$((REJECTED + 1)) ;;
                *)   OTHER=$((OTHER + 1)) ;;
            esac
            i=$((i + 1))
        done

        request GET "${SERVICE_URL}/api/v1/accounts/${LIVE_ACTIVE_ACCOUNT_ID}/balance" "${TOKEN}" ""
        BALANCE_AFTER="$(json_number "${HTTP_BODY}" cashBalance)"

        printf '  ....  %s order(s) at once: %s accepted, %s refused with 409, %s other\n' \
            "${LIVE_CONCURRENT_ORDERS}" "${ACCEPTED}" "${REJECTED}" "${OTHER}"

        if [ "${OTHER}" -gt 0 ]; then
            fail "${OTHER} of ${LIVE_CONCURRENT_ORDERS} concurrent orders failed with something other than 200 or 409." \
                "Contention is not an error. An order that loses the race is" \
                "refused with ORD-409, not answered with a 500, and never" \
                "answered with a balance computed from data that has moved."
        elif [ "${ACCEPTED}" -eq 0 ]; then
            skip "the lost-update check: every concurrent order was refused, so no cash moved."
        elif [ "${TERMINAL}" -eq 0 ] && [ "${WORKING}" -gt 0 ]; then
            skip "the lost-update check: the orders came back NEW, so the cash has not moved yet."
            note "the contract allows that: from Sprint 7 the endpoint records"
            note "the order and the executor settles it. Until then this probe"
            note "has nothing to reconcile, and the lock is reviewed live"
            note "against your mapper and your service."
        elif [ -z "${BALANCE_AFTER}" ]; then
            skip "the lost-update check: the balance endpoint returned nothing to compare against."
        else
            RECONCILED="$(awk -v before="${BALANCE_BEFORE}" -v after="${BALANCE_AFTER}" \
                -v filled="${TERMINAL}" -v qty="${LIVE_PROBE_QUANTITY}" -v price="${LIVE_PROBE_PRICE}" \
                'BEGIN {
                    expected = filled * qty * price
                    moved = before - after
                    diff = moved - expected
                    if (diff < 0) diff = -diff
                    printf "%s %.2f %.2f", (diff <= 0.005 ? "yes" : "no"), moved, expected
                 }')"
            VERDICT="${RECONCILED%% *}"
            MOVED="$(printf '%s' "${RECONCILED}" | awk '{print $2}')"
            EXPECTED="$(printf '%s' "${RECONCILED}" | awk '{print $3}')"

            if [ "${VERDICT}" = "yes" ]; then
                pass "the cash moved by ${MOVED} for ${TERMINAL} filled order(s), which reconciles"
                note "no update was lost in this run. Concurrency probes are"
                note "evidence rather than proof: one that passes once against a"
                note "read-then-write has only failed to hit the window."
            else
                fail "The cash moved by ${MOVED} and ${TERMINAL} filled order(s) should have moved ${EXPECTED}." \
                    "Balance before ${BALANCE_BEFORE}, after ${BALANCE_AFTER}." \
                    "That gap is a lost update. Two requests read the same" \
                    "balance, both computed a new one from what they read, and" \
                    "the second write overwrote the first. Both orders are in" \
                    "the history and only one of them was paid for." \
                    "The version has to be a predicate on the update rather" \
                    "than a check before it, and zero rows affected has to be" \
                    "treated as the refusal it is."
            fi
        fi
    fi
fi

# --- result ------------------------------------------------------------------

printf '\n%s\n' '----------------------------------------------------------------'
printf '%s passed, %s failed\n' "${PASSED}" "${FAILED}"

if [ "${FAILED}" -eq 0 ]; then
    if [ "${LIVE}" -eq 0 ]; then
        printf '\nThe harness is satisfied by the static checks. It has read your\n'
        printf 'build, your mappers, your compiled classes and your Dockerfile, and\n'
        printf 'it has never placed an order. Run it again with --live once your\n'
        printf 'stack is up.\n'
    else
        printf '\nThe harness is satisfied. It has placed orders and read the answers\n'
        printf 'without knowing whether the right rows were written, and it has\n'
        printf 'confirmed that an annotation is present without knowing whether the\n'
        printf 'transaction boundary is where it should be.\n'
    fi
    printf '\nAssessed by a human at the review: whether the transaction encloses\n'
    printf 'the work that has to be atomic and nothing more, whether every domain\n'
    printf 'exception leaves as its documented code, whether the response bodies\n'
    printf 'match the contract field for field, and whether the layering holds\n'
    printf 'where a grep cannot see it.\n'
    exit 0
fi

printf '\nEach failure above says what was expected and where to look. The\n'
printf 'transaction boundary, the completeness of the error mapping and the\n'
printf 'layering inside a class are assessed at the review, not here.\n'

exit 1
