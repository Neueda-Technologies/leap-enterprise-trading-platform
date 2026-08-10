#!/usr/bin/env bash
#
# Sprint 4 acceptance harness.
#
#   check.sh              run every check
#   check.sh --reuse      reuse the scratch venv from the last run
#   check.sh --keep       leave the scratch venv in place even on success
#
# The harness builds a scratch virtual environment, installs this folder into
# it as a package, and runs your test suite there. It touches nothing outside
# this folder, needs no database and no container, and never calls the
# Fauxnance API, so it costs nothing against your daily quota.
#
# It reads the names of your pipeline functions and your malformed-input test
# from manifest.env, so it asserts your design rather than dictating one.
#
# Passing these checks is necessary and not sufficient. Whether a claim is
# true, whether the chart supports it, and whether a reader outside the team
# can read that chart unaided are assessed by your instructor.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPRINT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

TESTS_DIR="${SPRINT_DIR}/tests"
FIXTURES_DIR="${SPRINT_DIR}/fixtures"
MANIFEST="${SPRINT_DIR}/manifest.env"
CLAIMS="${SPRINT_DIR}/claims.md"

# A transform covered by one happy path and one malformed case, plus whatever
# you write around extract and load, comes to more than this.
MIN_TESTS=4
MIN_CLAIMS=3
MIN_CLAIM_LENGTH=25

KEEP_VENV=0
REUSE_VENV=0
while [ "$#" -gt 0 ]; do
    case "$1" in
        --keep) KEEP_VENV=1; shift ;;
        --reuse) REUSE_VENV=1; shift ;;
        -h|--help) sed -n '2,20p' "${BASH_SOURCE[0]}" | sed 's/^#\{1,2\} \{0,1\}//'; exit 0 ;;
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

printf 'Sprint 4 acceptance harness\n'
printf 'Nothing here calls Fauxnance. No request is spent running it.\n'

# --- the manifest ------------------------------------------------------------

section 'Manifest'

[ -f "${MANIFEST}" ] || abort \
    "No manifest.env in ${SPRINT_DIR}." \
    "The harness reads the names of your pipeline functions from that file. If" \
    "you have deleted it, restore it from the repository."

PACKAGE_NAME=""
EXTRACT_CALLABLE=""
TRANSFORM_CALLABLE=""
LOAD_CALLABLE=""
MALFORMED_CASE_TEST=""

# shellcheck source=/dev/null
. "${MANIFEST}"

MANIFEST_KEYS="PACKAGE_NAME EXTRACT_CALLABLE TRANSFORM_CALLABLE LOAD_CALLABLE
MALFORMED_CASE_TEST"

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
        "Declare the importable package, the three pipeline functions as" \
        "module:function, and the malformed-input test as a pytest node id." \
        "Examples are in the file." \
        "On day one of the sprint this is the expected result: write the" \
        "extract function first, declare it, and come back."
fi

printf '%s' "${PACKAGE_NAME}" \
    | grep -qE '^[A-Za-z_][A-Za-z0-9_]*$' || abort \
    "PACKAGE_NAME in manifest.env is not an importable package name: ${PACKAGE_NAME}" \
    "Give the name a teammate types after import, for example analytics. Not a" \
    "path, not a directory, and not a distribution name with hyphens in it."

valid_callable() {
    spec="$1"
    case "${spec}" in
        *:*) ;;
        *) return 1 ;;
    esac
    module="${spec%%:*}"
    attribute="${spec##*:}"
    printf '%s' "${module}" \
        | grep -qE '^[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)*$' || return 1
    printf '%s' "${attribute}" | grep -qE '^[A-Za-z_][A-Za-z0-9_]*$' || return 1
    return 0
}

for key in EXTRACT_CALLABLE TRANSFORM_CALLABLE LOAD_CALLABLE; do
    eval "value=\${${key}}"
    valid_callable "${value}" || abort \
        "${key} in manifest.env is not written as module:function: ${value}" \
        "Write the importable module path, a colon, and the function name:" \
        "  ${key}=${PACKAGE_NAME}.etl.extract:fetch_candles"
done

case "${MALFORMED_CASE_TEST}" in
    tests/*::*) ;;
    *) abort \
        "MALFORMED_CASE_TEST is not a pytest node id under tests/: ${MALFORMED_CASE_TEST}" \
        "One test, named exactly, with the path and the test function separated" \
        "by two colons:" \
        "  MALFORMED_CASE_TEST=tests/test_transform.py::test_rejects_a_high_below_a_low" \
        "A file or a directory is not enough. The harness runs this one test on" \
        "its own so that a failure names the case that broke." ;;
esac

pass "manifest.env declares every name the harness needs"

# --- files on disk -----------------------------------------------------------

section 'Deliverables on disk'

TEST_FILES="$(find "${TESTS_DIR}" -maxdepth 2 -type f -name 'test_*.py' 2>/dev/null | wc -l | tr -d ' ')"
if [ "${TEST_FILES}" -ge 1 ]; then
    pass "tests/ holds ${TEST_FILES} test file(s)"
else
    abort "No test files in tests/." \
        "The acceptance criteria require pytest over at least the transform" \
        "step, including one malformed-input case. Put them in tests/ in this" \
        "folder and name the files test_*.py, so that the node id you declare" \
        "in manifest.env resolves."
fi

MISSING_FIXTURES=""
for fixture in candles-reliance-ns-2026-07.json candles-infy-ns-2026-07.json candles-malformed.json; do
    [ -s "${FIXTURES_DIR}/${fixture}" ] || MISSING_FIXTURES="${MISSING_FIXTURES} ${fixture}"
done
if [ -z "${MISSING_FIXTURES}" ]; then
    pass "the canned Fauxnance responses are all present in fixtures/"
else
    fail "Missing or empty fixture(s):${MISSING_FIXTURES}" \
        "These are shipped with the sprint so that the suite never touches the" \
        "network. Restore them from the repository. Add your own alongside" \
        "them, do not replace them."
fi

if [ -s "${CLAIMS}" ]; then
    pass "claims.md is present"
else
    abort "No claims.md in ${SPRINT_DIR}, or the file is empty." \
        "Three claims and the chart backing each one are the deliverable." \
        "Restore the file from the repository and fill in the table."
fi

# --- the interpreter ---------------------------------------------------------

section 'Toolchain'

command -v python3 >/dev/null 2>&1 || abort \
    "python3 is not on your PATH." \
    "Install Python 3.12 or later and try again."

python3 -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 12) else 1)' || abort \
    "python3 is older than 3.12: $(python3 -c 'import platform; print(platform.python_version())')" \
    "Target 3.12 or later, and say so in your packaging metadata. Install a" \
    "current Python, or point the harness at one by putting it first on your" \
    "PATH."

pass "python3 is $(python3 -c 'import platform; print(platform.python_version())')"

# --- secrets -----------------------------------------------------------------

section 'Secrets'

# A Fauxnance key is fnx_, the cohort, an underscore and 32 characters. Nothing
# resembling one belongs in a file that is committed.
KEY_PATTERN='fnx_[A-Za-z0-9-]+_[A-Za-z0-9]{16,}'

# The base URL carrying a credential in the query string, which is the other
# way a key reaches a commit.
URL_KEY_PATTERN='execute-api[^[:space:]]*[?&](api[_-]?key|apikey|key)='

# The key assigned as a literal rather than read from the environment, and a
# long literal set as the X-Api-Key header.
LITERAL_PATTERN='(FAUXNANCE_API_KEY["'"'"']?[[:space:]]*[:=][[:space:]]*["'"'"'][^"'"'"']+["'"'"'])|(X-Api-Key["'"'"']?[[:space:]]*[:=][[:space:]]*["'"'"'][A-Za-z0-9_-]{20,}["'"'"'])'

scan_for() {
    grep -rInE "$1" "${SPRINT_DIR}" \
        --exclude-dir=.check-venv \
        --exclude-dir=.venv \
        --exclude-dir=venv \
        --exclude-dir=.cache \
        --exclude-dir=.git \
        --exclude-dir=__pycache__ \
        --exclude-dir=.pytest_cache \
        --exclude-dir=build \
        --exclude-dir=dist \
        --exclude-dir='*.egg-info' \
        2>/dev/null | sed "s|^${SPRINT_DIR}/||" || true
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
    pass "no key literal, and no base URL carrying a key, anywhere in this folder"
else
    fail "Something that looks like a Fauxnance key is in a committed file." \
        ${LEAKS[@]+"${LEAKS[@]}"} \
        "Revoke the key with your instructor, then remove it. Deleting the line" \
        "does not remove it from the history, so tell your instructor either" \
        "way. Read the key from FAUXNANCE_API_KEY and nowhere else."
fi

# The name has to appear in code rather than in prose, so this parses every
# module outside the test suite and ignores docstrings and comments.
ENV_READS="$(python3 - "${SPRINT_DIR}" <<'PY' 2>/dev/null || true
import ast
import pathlib
import sys

NEEDLE = "FAUXNANCE_API_KEY"
SKIP = {
    ".cache",
    ".check-venv",
    ".pytest_cache",
    ".venv",
    "__pycache__",
    "build",
    "dist",
    "tests",
    "venv",
}
root = pathlib.Path(sys.argv[1])

for path in sorted(root.rglob("*.py")):
    parts = path.relative_to(root).parts
    if any(part in SKIP or part.endswith(".egg-info") for part in parts):
        continue
    try:
        tree = ast.parse(path.read_text(encoding="utf-8"))
    except (OSError, SyntaxError):
        continue
    docstrings = set()
    for node in ast.walk(tree):
        body = getattr(node, "body", None)
        if not isinstance(body, list) or not body:
            continue
        first = body[0]
        if isinstance(first, ast.Expr) and isinstance(first.value, ast.Constant) \
                and isinstance(first.value.value, str):
            docstrings.add(id(first.value))
    for node in ast.walk(tree):
        if isinstance(node, ast.Constant) and isinstance(node.value, str) \
                and NEEDLE in node.value and id(node) not in docstrings:
            print(f"{path.relative_to(root)}:{node.lineno}")
PY
)"

if [ -n "${ENV_READS}" ]; then
    pass "the package reads the key from FAUXNANCE_API_KEY"
else
    fail "No module outside tests/ names FAUXNANCE_API_KEY." \
        "The criteria require the key to be read from the environment. Copy" \
        ".env.example at the repository root to .env, put your key there, and" \
        "read it with os.environ or python-dotenv." \
        "Docstrings and comments do not count. The check is still a weak one:" \
        "it proves the name is used, not that it is the only source of the key."
fi

# --- the scratch environment -------------------------------------------------

section 'Installing into a scratch environment'

VENV_DIR="${CHECK_VENV:-${SPRINT_DIR}/.check-venv}"
VENV_PY="${VENV_DIR}/bin/python"

INSTALL_LOG="$(mktemp)"
trap 'rm -f "${INSTALL_LOG}"' EXIT

if [ "${REUSE_VENV}" -eq 1 ] && [ -x "${VENV_PY}" ]; then
    pass "reusing the scratch environment at $(basename "${VENV_DIR}")"
else
    rm -rf "${VENV_DIR}"
    if ! python3 -m venv "${VENV_DIR}" >"${INSTALL_LOG}" 2>&1; then
        sed 's/^/  | /' "${INSTALL_LOG}"
        abort "Could not create a virtual environment at ${VENV_DIR}." \
            "On Debian and Ubuntu this usually means python3-venv is not" \
            "installed."
    fi

    if "${VENV_PY}" -m pip install --quiet --disable-pip-version-check \
        -e "${SPRINT_DIR}[dev]" >"${INSTALL_LOG}" 2>&1; then
        pass "the package and its test dependencies install into a clean environment"
    else
        printf '\n'
        sed 's/^/  | /' "${INSTALL_LOG}" | tail -n 30
        abort "pip could not install this folder as a package." \
            "The output above is from installing it into an environment with" \
            "nothing in it, which is the state a teammate cloning the" \
            "repository starts from. The packaging contract for this sprint is" \
            "one installable project rooted here: packaging metadata in this" \
            "folder naming the package and its dependencies, your modules in an" \
            "importable package, and an optional dependency group called dev" \
            "that brings pytest." \
            "Run it yourself to see the whole output:" \
            "  python3 -m venv .check-venv" \
            "  .check-venv/bin/python -m pip install -e '${SPRINT_DIR}[dev]'"
    fi
fi

# pip warns rather than fails when an extra it was asked for does not exist, so
# the dev extra is checked on its own.
if "${VENV_PY}" -c 'import pytest' >/dev/null 2>&1; then
    pass "the dev extra brings pytest into the environment"
else
    abort "pytest is not in the scratch environment after installing '[dev]'." \
        "pip does not fail when an extra it was asked for is missing: it warns" \
        "and carries on. Declare an optional dependency group called dev that" \
        "includes pytest, so that one install command leaves a teammate with a" \
        "suite they can run."
fi

if (cd / && "${VENV_PY}" -c "import ${PACKAGE_NAME}") >/dev/null 2>&1; then
    pass "import ${PACKAGE_NAME} works from the installed environment"
else
    abort "import ${PACKAGE_NAME} fails in an environment where your project is installed." \
        "The install succeeded, so something was built, but the package named" \
        "in manifest.env is not in it. Usually the build backend was not told" \
        "which directory holds the package, or PACKAGE_NAME does not match the" \
        "directory it built."
fi

# --- the shape of the pipeline -----------------------------------------------

section 'Pipeline shape'

SHAPE_REPORT="$(cd / && "${VENV_PY}" - \
    "${EXTRACT_CALLABLE}" "${TRANSFORM_CALLABLE}" "${LOAD_CALLABLE}" <<'PY' 2>&1 || true
import importlib
import sys

specs = dict(zip(("extract", "transform", "load"), sys.argv[1:4]))
modules = {}

for label, spec in specs.items():
    module_name, _, attribute = spec.partition(":")
    try:
        module = importlib.import_module(module_name)
    except Exception as exc:
        print(f"{label}|IMPORT_FAILED|{type(exc).__name__}: {exc}")
        continue
    target = getattr(module, attribute, None)
    if target is None:
        available = ", ".join(n for n in vars(module) if not n.startswith("_")) or "nothing public"
        print(f"{label}|NO_ATTRIBUTE|{module_name} defines {available}")
        continue
    if not callable(target):
        print(f"{label}|NOT_CALLABLE|{spec} is a {type(target).__name__}")
        continue
    modules[label] = module_name
    print(f"{label}|OK|{spec}")

if len(modules) < 3:
    print("separation|SKIPPED|a step could not be resolved")
else:
    distinct = sorted(set(modules.values()))
    status = "OK" if len(distinct) == 3 else "SHARED"
    print(f"separation|{status}|{', '.join(distinct)}")
PY
)"

while IFS='|' read -r label status detail; do
    [ -n "${label}" ] || continue
    case "${label}:${status}" in
        separation:OK)
            pass "extract, transform and load live in three separate modules" ;;
        separation:SHARED)
            fail "The three steps do not live in three separate modules: ${detail}" \
                "The criteria ask for extract, transform and load as separable" \
                "functions. Separable means the transform can be imported and" \
                "tested without the module that opens a socket coming with it." ;;
        separation:SKIPPED)
            : ;;
        *:OK)
            pass "${label} resolves to ${detail}" ;;
        *:IMPORT_FAILED)
            fail "The module holding ${label} would not import: ${detail}" \
                "The harness imported it from a clean install of your package." \
                "An import that works from your editor and not from an install" \
                "is usually a path assumption or a dependency you have locally" \
                "and did not declare." ;;
        *:NO_ATTRIBUTE)
            fail "The ${label} function named in manifest.env does not exist." \
                "${detail}" \
                "Either write it, or correct the name in manifest.env." ;;
        *:NOT_CALLABLE)
            fail "The ${label} name in manifest.env is not a function: ${detail}" \
                "Declare the function itself, not a constant or a module." ;;
        *)
            fail "The harness could not read its own report for ${label}." \
                "${status} ${detail}" ;;
    esac
done <<EOF
${SHAPE_REPORT}
EOF

# --- the tests ---------------------------------------------------------------

section 'Tests'

TEST_LOG="$(mktemp)"
trap 'rm -f "${INSTALL_LOG}" "${TEST_LOG}"' EXIT

COLLECT_OUT="$( (cd "${SPRINT_DIR}" && "${VENV_PY}" -m pytest --collect-only -q) 2>&1 || true)"
TEST_COUNT="$(printf '%s\n' "${COLLECT_OUT}" | grep -c '::' || true)"

if [ "${TEST_COUNT}" -ge "${MIN_TESTS}" ]; then
    pass "${TEST_COUNT} test(s) collected"
else
    fail "Only ${TEST_COUNT} test(s) collected, and ${MIN_TESTS} is the minimum." \
        "One happy path and one malformed case over the transform, and" \
        "whatever you write around extract and load, comes to more than that."
fi

if (cd "${SPRINT_DIR}" && "${VENV_PY}" -m pytest -q) >"${TEST_LOG}" 2>&1; then
    pass "the whole suite passes"
else
    printf '\n'
    tail -n 25 "${TEST_LOG}" | sed 's/^/  | /'
    fail "The test suite does not pass." \
        "The output above is the tail of the run. Reproduce it with:" \
        "  ${VENV_PY} -m pytest"
fi

MALFORMED_STATUS=0
(cd "${SPRINT_DIR}" && "${VENV_PY}" -m pytest -q "${MALFORMED_CASE_TEST}") \
    >"${TEST_LOG}" 2>&1 || MALFORMED_STATUS=$?

case "${MALFORMED_STATUS}" in
    0)
        pass "the malformed-input case passes: ${MALFORMED_CASE_TEST}" ;;
    4|5)
        fail "No test matches MALFORMED_CASE_TEST: ${MALFORMED_CASE_TEST}" \
            "pytest collected nothing under that node id. Check the path and" \
            "the test function name, and that the file is under tests/." ;;
    *)
        tail -n 20 "${TEST_LOG}" | sed 's/^/  | /'
        fail "The malformed-input case fails: ${MALFORMED_CASE_TEST}" ;;
esac

note "the harness runs that test, it does not read it. A test that asserts"
note "nothing passes here and fails in the review."

# --- the claims --------------------------------------------------------------

section 'Claims'

CLAIM_ROWS="$(awk -F'|' '
    /^[[:space:]]*\|/ {
        number = $2; claim = $3; artefact = $4;
        gsub(/^[ \t]+|[ \t]+$/, "", number);
        gsub(/^[ \t]+|[ \t]+$/, "", claim);
        gsub(/^[ \t]+|[ \t]+$/, "", artefact);
        if (number ~ /^[0-9]+$/) printf "%s\t%s\t%s\n", number, claim, artefact;
    }
' "${CLAIMS}")"

COMPLETE_CLAIMS=0
CLAIM_PROBLEMS=()

while IFS=$'\t' read -r number claim artefact; do
    [ -n "${number}" ] || continue
    problem=""

    case "${claim}" in
        ''|*CHANGE_ME*) problem="claim ${number} is still a placeholder" ;;
    esac

    if [ -z "${problem}" ] && [ "${#claim}" -lt "${MIN_CLAIM_LENGTH}" ]; then
        problem="claim ${number} is ${#claim} characters, too short to be a claim"
    fi

    if [ -z "${problem}" ]; then
        case "${artefact}" in
            ''|*CHANGE_ME*) problem="claim ${number} names no chart artefact" ;;
            *)
                path="${SPRINT_DIR}/${artefact%%#*}"
                [ -s "${path}" ] || problem="claim ${number} names ${artefact%%#*}, which is not a file in this folder"
                ;;
        esac
    fi

    if [ -n "${problem}" ]; then
        CLAIM_PROBLEMS[${#CLAIM_PROBLEMS[@]}]="${problem}"
    else
        COMPLETE_CLAIMS=$((COMPLETE_CLAIMS + 1))
    fi
done <<EOF
${CLAIM_ROWS}
EOF

if [ "${COMPLETE_CLAIMS}" -ge "${MIN_CLAIMS}" ]; then
    pass "${COMPLETE_CLAIMS} claim(s) stated, each naming a committed chart"
else
    fail "Only ${COMPLETE_CLAIMS} of the ${MIN_CLAIMS} required claims are complete in claims.md." \
        ${CLAIM_PROBLEMS[@]+"${CLAIM_PROBLEMS[@]}"} \
        "A row counts when the claim is written out, is longer than" \
        "${MIN_CLAIM_LENGTH} characters, and names a chart file that exists in" \
        "this folder. Commit the charts: a dashboard that only exists on the" \
        "machine that built it cannot be assessed."
fi

note "the harness reads the length of a claim, not its truth. Whether the"
note "claim holds, and whether the chart supports it, is assessed by a human."

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
    printf '\nThe harness is satisfied. It has not looked at a chart, checked a\n'
    printf 'number against the data behind it, or decided whether a reader outside\n'
    printf 'your team could read any of it. That happens in the review.\n'
    exit 0
fi

exit 1
