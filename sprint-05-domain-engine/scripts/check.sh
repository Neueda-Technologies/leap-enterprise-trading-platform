#!/usr/bin/env bash
#
# Sprint 5 acceptance harness.
#
#   check.sh              run every check
#   check.sh --offline    run Maven offline, from the artefacts already cached
#
# The harness builds your module from a clean state, runs your suite, reads the
# compiled classes to check the enumerations and the exception hierarchy, and
# reads the dependency tree to check that nothing forbidden reached the
# classpath. It touches nothing outside this folder, needs no database and no
# container, and never calls the Fauxnance API.
#
# It reads your base package and your six exception class names from
# manifest.env, so it asserts your design rather than dictating one.
#
# Passing these checks is necessary and not sufficient. Whether the eight rules
# are correct, whether the tests came before the code, and whether the diagrams
# describe the code you wrote are assessed at the design review.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPRINT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

POM="${SPRINT_DIR}/pom.xml"
MAIN_SRC="${SPRINT_DIR}/src/main/java"
TEST_SRC="${SPRINT_DIR}/src/test/java"
CLASSES_DIR="${SPRINT_DIR}/target/classes"
REPORTS_DIR="${SPRINT_DIR}/target/surefire-reports"
MANIFEST="${SPRINT_DIR}/manifest.env"

# Eight rules firing and eight not firing is sixteen in OrderLogicTest alone,
# six DTO fields is six more, and AccountTest cannot cover status, debit,
# credit, affordability and money drift in fewer than a handful. The floor is
# arithmetic, not ambition.
MIN_NAMED_TESTS=24

# The three test classes named in the acceptance criteria.
NAMED_TEST_CLASSES="AccountTest OrderLogicTest PlaceOrderRequestValidationTest"

MVN_FLAGS=(-B)

while [ "$#" -gt 0 ]; do
    case "$1" in
        --offline) MVN_FLAGS+=(-o); shift ;;
        -h|--help) sed -n '2,19p' "${BASH_SOURCE[0]}" | sed 's/^#\{1,2\} \{0,1\}//'; exit 0 ;;
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

printf 'Sprint 5 acceptance harness\n'
printf 'No container, no database and no network call to Fauxnance.\n'

# --- the project -------------------------------------------------------------

section 'The project'

[ -f "${POM}" ] || abort \
    "No pom.xml in ${SPRINT_DIR}." \
    "The engineering contract for this sprint is one Maven project rooted" \
    "here: Java 21, JUnit 5 and surefire, sources under src/main/java and" \
    "tests under src/test/java, with jakarta.validation-api as the only" \
    "non-test dependency." \
    "Write that pom and commit it, because every check below reads the" \
    "module it describes and a teammate cloning this repository has nothing" \
    "to compile without it."
pass "pom.xml is present"

# --- the manifest ------------------------------------------------------------

section 'Manifest'

[ -f "${MANIFEST}" ] || abort \
    "No manifest.env in ${SPRINT_DIR}." \
    "The harness reads your base package and your exception class names from" \
    "that file. If you have deleted it, restore it from the repository."

BASE_PACKAGE=""
EXCEPTION_BASE=""
# The six below are read back by name through eval, further down, so that the
# manifest keys and the check loop stay in one list.
# shellcheck disable=SC2034
EXCEPTION_ACCOUNT_NOT_FOUND=""
# shellcheck disable=SC2034
EXCEPTION_ACCOUNT_NOT_ACTIVE=""
# shellcheck disable=SC2034
EXCEPTION_INSTRUMENT_NOT_FOUND=""
# shellcheck disable=SC2034
EXCEPTION_INSUFFICIENT_FUNDS=""
# shellcheck disable=SC2034
EXCEPTION_INSUFFICIENT_HOLDINGS=""
# shellcheck disable=SC2034
EXCEPTION_DUPLICATE_ORDER=""

# shellcheck source=/dev/null
. "${MANIFEST}"

EXCEPTION_KEYS="EXCEPTION_ACCOUNT_NOT_FOUND EXCEPTION_ACCOUNT_NOT_ACTIVE
EXCEPTION_INSTRUMENT_NOT_FOUND EXCEPTION_INSUFFICIENT_FUNDS
EXCEPTION_INSUFFICIENT_HOLDINGS EXCEPTION_DUPLICATE_ORDER"

MANIFEST_KEYS="BASE_PACKAGE EXCEPTION_BASE ${EXCEPTION_KEYS}"

OUTSTANDING=""
for key in ${MANIFEST_KEYS}; do
    eval "value=\${${key}}"
    if [ -z "${value}" ] || [ "${value}" = "CHANGE_ME" ]; then
        OUTSTANDING="${OUTSTANDING} ${key}"
    fi
done

if [ -n "${OUTSTANDING}" ]; then
    abort "manifest.env is not filled in." \
        "Still empty or set to CHANGE_ME:${OUTSTANDING}" \
        "Declare the package your domain types live under and the six" \
        "exception classes. Examples are in the file." \
        "On day one of the sprint this is the expected result: write the" \
        "first failing test, declare what it names, and come back."
fi

printf '%s' "${BASE_PACKAGE}" \
    | grep -qE '^[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)*$' || abort \
    "BASE_PACKAGE in manifest.env is not a Java package name: ${BASE_PACKAGE}" \
    "Write it as it appears in your package declaration, for example" \
    "  BASE_PACKAGE=com.tradingplatform.domain"

for key in EXCEPTION_BASE ${EXCEPTION_KEYS}; do
    eval "value=\${${key}}"
    printf '%s' "${value}" | grep -qE '^[A-Za-z_][A-Za-z0-9_]*$' || abort \
        "${key} in manifest.env is not a simple class name: ${value}" \
        "Give the class name on its own, without the package. The harness" \
        "finds it under BASE_PACKAGE for you."
done

pass "manifest.env declares every name the harness needs"

BASE_PATH="${BASE_PACKAGE//.//}"

# --- files on disk -----------------------------------------------------------

section 'Deliverables on disk'

MAIN_SOURCES="$(find "${MAIN_SRC}" -type f -name '*.java' 2>/dev/null | wc -l | tr -d ' ')"
TEST_SOURCES="$(find "${TEST_SRC}" -type f -name '*.java' 2>/dev/null | wc -l | tr -d ' ')"

if [ "${MAIN_SOURCES}" -ge 1 ]; then
    pass "src/main/java holds ${MAIN_SOURCES} source file(s)"
else
    abort "No Java source under src/main/java." \
        "The four entities, the three enumerations, the DTO, the exception" \
        "hierarchy and the rules are yours to design from the brief, and the" \
        "harness reads them from the Maven source directory." \
        "On day one of the sprint this is the expected result. Write the" \
        "first failing test, commit it, make it pass, and come back."
fi

if [ "${TEST_SOURCES}" -ge 1 ]; then
    pass "src/test/java holds ${TEST_SOURCES} source file(s)"
else
    abort "No Java source under src/test/java." \
        "The criteria require the tests to arrive before the implementation," \
        "so an empty test tree beside a full main tree is a finding in" \
        "itself. Name the three classes the criteria name:" \
        "  AccountTest, OrderLogicTest, PlaceOrderRequestValidationTest"
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

pass "mvn and javap are on the PATH"

# --- the build ---------------------------------------------------------------

section 'Building from a clean state'

BUILD_LOG="$(mktemp)"
TEST_LOG="$(mktemp)"
TREE_LOG="$(mktemp)"
trap 'rm -f "${BUILD_LOG}" "${TEST_LOG}" "${TREE_LOG}"' EXIT

if (cd "${SPRINT_DIR}" && mvn "${MVN_FLAGS[@]}" clean test-compile) >"${BUILD_LOG}" 2>&1; then
    pass "mvn clean test-compile succeeds"
else
    printf '\n'
    tail -n 30 "${BUILD_LOG}" | sed 's/^/  | /'
    abort "The build does not succeed from a clean state." \
        "The output above is the tail of the build. A module that compiles" \
        "only from a target directory somebody else's build left behind is" \
        "not a deliverable." \
        "Reproduce it with:" \
        "  cd ${SPRINT_DIR} && mvn clean test-compile" \
        "If the failure is a banned-dependencies rule in your own pom, the" \
        "dependency it names belongs in Sprint 6 rather than here."
fi

if [ -d "${CLASSES_DIR}/${BASE_PATH}" ]; then
    pass "compiled classes are under ${BASE_PACKAGE}"
else
    abort "Nothing compiled under ${BASE_PACKAGE}." \
        "BASE_PACKAGE in manifest.env says ${BASE_PACKAGE}, and no class" \
        "landed at target/classes/${BASE_PATH}. Either correct the manifest" \
        "or move the package."
fi

# --- the tests ---------------------------------------------------------------

section 'Tests'

SUITE_STATUS=0
(cd "${SPRINT_DIR}" && mvn "${MVN_FLAGS[@]}" test) >"${TEST_LOG}" 2>&1 || SUITE_STATUS=$?

if [ "${SUITE_STATUS}" -eq 0 ]; then
    pass "the whole suite passes"
else
    printf '\n'
    grep -E '^\[ERROR\]|Tests run:' "${TEST_LOG}" | tail -n 25 | sed 's/^/  | /'
    fail "The test suite does not pass." \
        "The output above is the failing part of the run. Reproduce it with:" \
        "  cd ${SPRINT_DIR} && mvn test"
fi

report_for() {
    find "${REPORTS_DIR}" -maxdepth 1 -type f \
        \( -name "TEST-*.${1}.xml" -o -name "TEST-${1}.xml" \) 2>/dev/null | head -n 1
}

NAMED_TEST_TOTAL=0
MISSING_CLASSES=""

for class in ${NAMED_TEST_CLASSES}; do
    report="$(report_for "${class}")"
    if [ -z "${report}" ]; then
        MISSING_CLASSES="${MISSING_CLASSES} ${class}"
        continue
    fi

    cases="$(grep -c '<testcase ' "${report}" || true)"
    broken="$(grep -cE '<(failure|error)[ >/]' "${report}" || true)"
    NAMED_TEST_TOTAL=$((NAMED_TEST_TOTAL + cases))

    if [ "${broken}" -eq 0 ]; then
        pass "${class} ran ${cases} test(s), all green"
    else
        fail "${class} ran ${cases} test(s) and ${broken} did not pass." \
            "The criteria name this class and require it green. Its report" \
            "is at ${report#"${SPRINT_DIR}/"}."
    fi
done

if [ -n "${MISSING_CLASSES}" ]; then
    fail "No test report for:${MISSING_CLASSES}" \
        "The acceptance criteria name AccountTest, OrderLogicTest and" \
        "PlaceOrderRequestValidationTest, and all three must be green. The" \
        "package is yours; the class name is not." \
        "A class that exists but produced no report was not run. Check the" \
        "name, that it holds at least one test method, and that surefire is" \
        "in your build."
fi

if [ "${NAMED_TEST_TOTAL}" -ge "${MIN_NAMED_TESTS}" ]; then
    pass "${NAMED_TEST_TOTAL} test(s) across the named classes that ran"
else
    fail "Only ${NAMED_TEST_TOTAL} test(s) across the named classes that ran, and ${MIN_NAMED_TESTS} is the minimum." \
        "Eight rules firing and eight not firing is sixteen in" \
        "OrderLogicTest on its own, and six DTO fields is six more." \
        "Tests in your other classes are worth writing and do not count" \
        "towards this number."
fi

# --- the enumerations --------------------------------------------------------

section 'Enumerations'

find_class() {
    find "${CLASSES_DIR}/${BASE_PATH}" -type f -name "${1}.class" 2>/dev/null | head -n 1
}

fqn_of() {
    path="${1#"${CLASSES_DIR}/"}"
    path="${path%.class}"
    printf '%s' "${path//\//.}"
}

enum_literals() {
    javap -cp "${CLASSES_DIR}" "$1" 2>/dev/null \
        | awk -v type="$1" '
            index($0, "public static final " type " ") > 0 {
                name = $NF
                sub(/;$/, "", name)
                print name
            }' \
        | sort
}

check_enum() {
    simple="$1"
    shift
    expected="$(printf '%s\n' "$@" | sort)"

    path="$(find_class "${simple}")"
    if [ -z "${path}" ]; then
        fail "No compiled class named ${simple} under ${BASE_PACKAGE}." \
            "The acceptance criteria name this enumeration. The package is" \
            "yours; the name is not. Its literals are:" \
            "  $*"
        return
    fi

    fqn="$(fqn_of "${path}")"

    if ! javap -cp "${CLASSES_DIR}" "${fqn}" 2>/dev/null | grep -q 'extends java.lang.Enum'; then
        fail "${fqn} is not an enum." \
            "A class holding string constants is not the same thing. The" \
            "contract types are enumerations, the database stores their" \
            "names, and the Angular client generates a union type from them."
        return
    fi

    found="$(enum_literals "${fqn}")"
    missing="$(comm -23 <(printf '%s\n' "${expected}") <(printf '%s\n' "${found}") | tr '\n' ' ')"
    extra="$(comm -13 <(printf '%s\n' "${expected}") <(printf '%s\n' "${found}") | tr '\n' ' ')"
    missing="${missing% }"
    extra="${extra% }"

    if [ -z "${missing}" ] && [ -z "${extra}" ]; then
        pass "${simple} holds exactly: $*"
        return
    fi

    details=()
    [ -n "${missing}" ] && details+=("missing: ${missing}")
    [ -n "${extra}" ] && details+=("not in the contract: ${extra}")
    details+=("The contract says ${simple} is exactly: $*")
    details+=("These literals are in contracts/trade-api.yaml, in the database")
    details+=("and in the Angular types generated in Sprint 9. A renamed or")
    details+=("extra literal breaks all three.")

    fail "${fqn} does not match the contract." "${details[@]}"
}

check_enum AccountStatus ACTIVE SUSPENDED CLOSED
check_enum OrderSide BUY SELL
check_enum OrderStatus NEW FILLED REJECTED CANCELLED

# --- the exception hierarchy -------------------------------------------------

section 'Exception hierarchy'

superclass_of() {
    javap -cp "${CLASSES_DIR}" "$1" 2>/dev/null \
        | awk '
            /(^|[[:space:]])class[[:space:]]/ && !seen {
                for (i = 1; i < NF; i++) {
                    if ($i == "extends") {
                        parent = $(i + 1)
                        sub(/<.*$/, "", parent)
                        print parent
                        seen = 1
                    }
                }
            }'
}

descends_from() {
    current="$1"
    target="$2"
    depth=0
    while [ -n "${current}" ] && [ "${depth}" -lt 12 ]; do
        [ "${current}" = "${target}" ] && return 0
        current="$(superclass_of "${current}")"
        depth=$((depth + 1))
    done
    return 1
}

BASE_PATH_FOUND="$(find_class "${EXCEPTION_BASE}")"
BASE_FQN=""

if [ -z "${BASE_PATH_FOUND}" ]; then
    fail "No compiled class named ${EXCEPTION_BASE} under ${BASE_PACKAGE}." \
        "manifest.env declares that as the base every domain exception" \
        "extends. Either write it, or correct the name in the manifest."
else
    BASE_FQN="$(fqn_of "${BASE_PATH_FOUND}")"
    if descends_from "${BASE_FQN}" java.lang.RuntimeException; then
        pass "${BASE_FQN} is an unchecked exception"
    elif descends_from "${BASE_FQN}" java.lang.Throwable; then
        pass "${BASE_FQN} is a Throwable"
        note "it is a checked exception. A business rule failure is not"
        note "something a caller recovers from locally: it ends the request"
        note "and becomes a response. Be ready to defend the choice."
    else
        fail "${BASE_FQN} is not a Throwable." \
            "The six specified cases have to be raisable. Make the base" \
            "extend RuntimeException."
        BASE_FQN=""
    fi
fi

if [ -n "${BASE_FQN}" ]; then
    FOUND_EXCEPTIONS=0
    for key in ${EXCEPTION_KEYS}; do
        eval "simple=\${${key}}"
        path="$(find_class "${simple}")"

        if [ -z "${path}" ]; then
            fail "No compiled class named ${simple} under ${BASE_PACKAGE}." \
                "manifest.env declares it for ${key}. Either write it, or" \
                "correct the name in the manifest if you called it" \
                "something else."
            continue
        fi

        fqn="$(fqn_of "${path}")"

        if [ "${fqn}" = "${BASE_FQN}" ]; then
            fail "${key} names the base type itself: ${simple}" \
                "The six cases are six types. A single exception carrying a" \
                "code as a constructor argument cannot be caught apart from" \
                "the others, and Sprint 6 maps each one to its own status."
            continue
        fi

        if descends_from "${fqn}" "${BASE_FQN}"; then
            FOUND_EXCEPTIONS=$((FOUND_EXCEPTIONS + 1))
        else
            parent="$(superclass_of "${fqn}")"
            fail "${fqn} does not descend from ${BASE_FQN}." \
                "It extends ${parent:-nothing this harness could read}." \
                "One base type is what lets the Sprint 6 service catch every" \
                "rule failure in one place and map it to its documented code."
        fi
    done

    if [ "${FOUND_EXCEPTIONS}" -eq 6 ]; then
        pass "six exception types, all descending from ${BASE_FQN}"
    fi
fi

# --- the dependency tree -----------------------------------------------------

section 'Dependencies'

# Spring, the servlet API, the persistence framework, connection pools and
# every JDBC driver a team is likely to reach for. This reads the resolved
# tree, so it holds whether or not your own build bans them, and it catches an
# artefact that arrived transitively through something else.
FORBIDDEN='org\.springframework|jakarta\.servlet|javax\.servlet|org\.postgresql|[[:space:]]mysql:|com\.mysql|com\.h2database|org\.mariadb\.jdbc|com\.oracle\.database|com\.microsoft\.sqlserver|sqlite-jdbc|org\.mybatis|HikariCP'

if (cd "${SPRINT_DIR}" && mvn "${MVN_FLAGS[@]}" dependency:tree -DoutputType=text) >"${TREE_LOG}" 2>&1; then
    HITS="$(grep -E "${FORBIDDEN}" "${TREE_LOG}" | sed 's/^\[INFO\] *//' | sed 's/^/  /' || true)"
    if [ -z "${HITS}" ]; then
        pass "no Spring, servlet, JDBC, MyBatis or connection-pool artefact in the resolved dependency tree"
    else
        fail "Something the domain must not depend on is on the classpath." \
            "The domain is called from a Spring controller in Sprint 6 and" \
            "from a Kafka consumer in Sprint 7. A domain that has acquired a" \
            "framework or a driver can only be used by a caller that brought" \
            "the same one, and the second caller reimplements the rules." \
            "Offending entries:"
        printf '%s\n' "${HITS}" | sed 's/^/        /'
    fi
else
    tail -n 20 "${TREE_LOG}" | sed 's/^/  | /'
    fail "mvn dependency:tree did not run." \
        "The tail of the output is above. Until it runs, criterion 5 is" \
        "unchecked."
fi

# The enforcer rule is not required and is not assumed. Where it is configured,
# the boundary is enforced by the build itself, which fails sooner and tells
# whoever added the dependency why.
if grep -q 'maven-enforcer-plugin' "${POM}" 2>/dev/null \
    && grep -q 'bannedDependencies' "${POM}" 2>/dev/null; then
    pass "your own build bans them too, through the enforcer plugin"
else
    note "your build does not ban them itself. The check above is then the"
    note "only thing between this module and a framework somebody adds in a"
    note "hurry. An enforcer bannedDependencies rule fails the build instead."
fi

# --- result ------------------------------------------------------------------

printf '\n%s\n' '----------------------------------------------------------------'
printf '%s passed, %s failed\n' "${PASSED}" "${FAILED}"

if [ "${FAILED}" -eq 0 ]; then
    printf '\nThe harness is satisfied. It has counted tests without reading one,\n'
    printf 'confirmed that eight rules could be implemented without placing an\n'
    printf 'order, and never opened a diagram.\n'
    printf '\nAssessed by a human at the design review: whether each rule is\n'
    printf 'correct and in the right order, whether it lives in the domain\n'
    printf 'rather than in a caller, whether the commit history shows the tests\n'
    printf 'arriving before the code, and whether the class and sequence\n'
    printf 'diagrams match what you wrote.\n'
    exit 0
fi

printf '\nEach failure above says what was expected and where to look. Rule\n'
printf 'correctness, the test-first commit history and the diagrams are\n'
printf 'assessed at the design review, not here.\n'

exit 1
