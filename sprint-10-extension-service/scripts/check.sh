#!/usr/bin/env bash
#
# Sprint 10 acceptance harness.
#
#   check.sh              static checks only. No running service.
#   check.sh --live       the static checks, then the probes against your
#                         running stack.
#
# Static mode reads manifest.env, confirms the extension you declared is one of
# the six, counts the decision log entries that are not the template, and reads
# your security review.
#
# Live mode needs your stack up: your service, your Auth service, and whatever
# your extension consumes. It starts nothing and stops nothing. It calls your
# health endpoint, then puts three requests to one protected route: without a
# token, with a token signed by a key nobody holds, and with a real token from
# your Auth service. If you declared portfolio-pnl it also reads the two main
# routes from contracts/portfolio-api.yaml and checks the shape of the answers.
#
# This harness is shorter than the ones in earlier sprints, and deliberately so.
# Five of the six extensions have no contract for it to assert against and no
# scaffold for it to know the shape of. Most of this sprint is assessed by a
# person: whether the scope you agreed on Monday is the scope you delivered,
# whether the log records decisions rather than events, whether the review is a
# reading of your service, and whether the demonstration ran on live data.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPRINT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
MANIFEST="${SPRINT_DIR}/manifest.env"

# The catalogue, from README.md. One of these, exactly.
VALID_EXTENSIONS="portfolio-pnl trade-advice-signals watchlists-price-alerts
customer-notifications customer-preferences automated-strategy-execution"

LIVE=0
while [ "$#" -gt 0 ]; do
    case "$1" in
        --live) LIVE=1; shift ;;
        -h|--help) sed -n '2,25p' "${BASH_SOURCE[0]}" | sed 's/^#\{1,2\} \{0,1\}//'; exit 0 ;;
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

printf 'Sprint 10 acceptance harness\n'
if [ "${LIVE}" -eq 1 ]; then
    printf 'Static checks, then live probes against your running stack.\n'
else
    printf 'Static checks only. Add --live once your stack is up.\n'
fi

# --- the manifest --------------------------------------------------------------

section 'Manifest'

[ -f "${MANIFEST}" ] || abort \
    "No manifest.env in ${SPRINT_DIR}." \
    "The harness reads your extension, your document paths and the names live" \
    "mode needs from that file. If you have deleted it, restore it from the" \
    "repository."

EXTENSION=""
DECISION_LOG_DIR=""
DECISION_LOG_TEMPLATE=""
DECISION_LOG_MIN_ENTRIES=""
SECURITY_REVIEW_FILE=""
SECURITY_REVIEW_TEMPLATE=""
SECURITY_REVIEW_CATEGORIES=""
SECURITY_REVIEW_NONE_MIN_WORDS=""
SERVICE_HOST=""
SERVICE_PORT=""
HEALTH_PATH=""
PROTECTED_PATH=""
AUTH_HOST=""
AUTH_PORT=""
AUTH_LOGIN_PATH=""
DEMO_USERNAME=""
DEMO_PASSWORD=""
DEMO_ACCOUNT_ID=""
TOKEN_ISSUER=""
LOGIN_THROTTLE_COOLDOWN_SECONDS=""
CONTRACT_FILE=""

# shellcheck source=/dev/null
. "${MANIFEST}"

STATIC_KEYS="EXTENSION DECISION_LOG_DIR DECISION_LOG_TEMPLATE
DECISION_LOG_MIN_ENTRIES SECURITY_REVIEW_FILE SECURITY_REVIEW_CATEGORIES
SECURITY_REVIEW_NONE_MIN_WORDS"

LIVE_KEYS="SERVICE_HOST SERVICE_PORT HEALTH_PATH PROTECTED_PATH AUTH_HOST
AUTH_PORT AUTH_LOGIN_PATH DEMO_USERNAME DEMO_PASSWORD DEMO_ACCOUNT_ID
LOGIN_THROTTLE_COOLDOWN_SECONDS"

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
        "EXTENSION is the choice your team confirms with an instructor on day" \
        "one, and PROTECTED_PATH is a route on your service that requires a" \
        "token. Every other key ships with a defensible default: set the ones" \
        "your team decided differently and leave the rest alone." \
        "SECURITY_REVIEW_TEMPLATE, TOKEN_ISSUER and CONTRACT_FILE are optional," \
        "and an empty value there turns one check into a named skip."
fi

for key in DECISION_LOG_MIN_ENTRIES SECURITY_REVIEW_NONE_MIN_WORDS \
    LOGIN_THROTTLE_COOLDOWN_SECONDS; do
    eval "value=\${${key}}"
    if [ -n "${value}" ]; then
        printf '%s' "${value}" | grep -qE '^[0-9]+$' || abort \
            "${key} in manifest.env is not a whole number: ${value}"
    fi
done

EXTENSION_KNOWN=0
for candidate in ${VALID_EXTENSIONS}; do
    [ "${EXTENSION}" = "${candidate}" ] && EXTENSION_KNOWN=1
done

if [ "${EXTENSION_KNOWN}" -eq 0 ]; then
    abort "EXTENSION in manifest.env is ${EXTENSION}, which is not one of the six." \
        "The identifiers are, exactly:" \
        "  portfolio-pnl" \
        "  trade-advice-signals" \
        "  watchlists-price-alerts" \
        "  customer-notifications" \
        "  customer-preferences" \
        "  automated-strategy-execution" \
        "They are listed against the briefs in the catalogue table in README.md." \
        "A team building something outside the catalogue agreed that with an" \
        "instructor first, and the manifest still has to name the entry it was" \
        "agreed against."
fi

pass "manifest.env declares every name the harness needs"

BRIEF_PATH="${SPRINT_DIR}/catalogue/${EXTENSION}.md"
if [ -f "${BRIEF_PATH}" ]; then
    pass "the declared extension is ${EXTENSION}, briefed in catalogue/${EXTENSION}.md"
else
    fail "No catalogue/${EXTENSION}.md in ${SPRINT_DIR}." \
        "The brief ships with this folder and the harness reads its name from" \
        "EXTENSION. Restore it from the repository."
fi

if [ "${EXTENSION}" = "portfolio-pnl" ]; then
    note "contracts/portfolio-api.yaml binds this extension. Live mode reads two"
    note "of its routes and checks the shape of the answers."
else
    note "the API for this extension is your team's design, reviewed on day one."
    note "No script here knows its shape, so the routes are read at the review."
fi

LOG_DIR_PATH="${SPRINT_DIR}/${DECISION_LOG_DIR}"
LOG_TEMPLATE_PATH="${SPRINT_DIR}/${DECISION_LOG_TEMPLATE}"
REVIEW_PATH="${SPRINT_DIR}/${SECURITY_REVIEW_FILE}"
REVIEW_TEMPLATE_PATH=""
[ -n "${SECURITY_REVIEW_TEMPLATE}" ] && REVIEW_TEMPLATE_PATH="${SPRINT_DIR}/${SECURITY_REVIEW_TEMPLATE}"

# --- the decision log ------------------------------------------------------------

section 'The decision log'

if [ ! -d "${LOG_DIR_PATH}" ]; then
    fail "No ${DECISION_LOG_DIR} directory in ${SPRINT_DIR}." \
        "Criterion 6 is a committed decision log. The folder ships with the" \
        "template in it. Restore it, or correct DECISION_LOG_DIR in" \
        "manifest.env if you moved it."
elif [ ! -f "${LOG_TEMPLATE_PATH}" ]; then
    fail "No ${DECISION_LOG_TEMPLATE} in ${SPRINT_DIR}." \
        "The template is the committed shape of an entry, and the harness needs" \
        "it to tell a written entry from a copied one. Restore it from the" \
        "repository."
else
    TEMPLATE_NAME="$(basename "${LOG_TEMPLATE_PATH}")"
    ENTRIES=0
    LOG_PROBLEMS=""

    while IFS= read -r entry; do
        [ -n "${entry}" ] || continue
        name="$(basename "${entry}")"
        [ "${name}" = "${TEMPLATE_NAME}" ] && continue

        if cmp -s "${entry}" "${LOG_TEMPLATE_PATH}"; then
            LOG_PROBLEMS="${LOG_PROBLEMS}
        ${name}  byte for byte the template"
            continue
        fi

        missing=""
        for heading in Context 'Options considered' Decision Consequences; do
            grep -qE "^#{1,3}[[:space:]]+${heading}[[:space:]]*$" "${entry}" \
                || missing="${missing} ${heading},"
        done
        if [ -n "${missing}" ]; then
            LOG_PROBLEMS="${LOG_PROBLEMS}
        ${name}  no heading for:${missing%,}"
            continue
        fi

        if grep -q 'TODO' "${entry}"; then
            LOG_PROBLEMS="${LOG_PROBLEMS}
        ${name}  still carries a TODO from the template"
            continue
        fi

        ENTRIES=$((ENTRIES + 1))
    done < <(find "${LOG_DIR_PATH}" -maxdepth 1 -type f -name '*.md' | LC_ALL=C sort)

    if [ "${ENTRIES}" -ge "${DECISION_LOG_MIN_ENTRIES}" ]; then
        pass "${ENTRIES} decision log entr(ies), and the manifest asks for ${DECISION_LOG_MIN_ENTRIES}"
        note "a heading with something under it is all this can see. Whether an"
        note "entry records a decision or an event, whether the options were"
        note "genuinely considered, and whether the consequences admit a cost"
        note "are read at the review."
    else
        fail "${ENTRIES} filled-in decision log entr(ies) in ${DECISION_LOG_DIR}, and the manifest asks for ${DECISION_LOG_MIN_ENTRIES}." \
            "An entry counts when it is not the template, carries the four" \
            "headings the template uses, and has no TODO left in it." \
            "On day one this is the expected result. Write entries as you take" \
            "the decisions: a log assembled on Friday records what you built," \
            "which everyone can already see, and loses what you nearly did" \
            "instead."
    fi

    if [ -n "${LOG_PROBLEMS}" ]; then
        printf '        %s\n' "Files in ${DECISION_LOG_DIR} that were not counted:"
        printf '%s\n' "${LOG_PROBLEMS#$'\n'}"
    fi
fi

# --- the security review ---------------------------------------------------------

section 'The OWASP review'

if [ ! -f "${REVIEW_PATH}" ]; then
    fail "No ${SECURITY_REVIEW_FILE} in ${SPRINT_DIR}." \
        "Criterion 4 is a completed review of the new service, with its" \
        "findings addressed. Copy the Sprint 8 template into this folder and" \
        "fill it in as you build:" \
        "  mkdir -p $(dirname "${REVIEW_PATH}")" \
        "  cp ${SECURITY_REVIEW_TEMPLATE:-../sprint-08-auth-service/security-review/TEMPLATE.md} ${SECURITY_REVIEW_FILE}" \
        "If yours is named something else, say so in SECURITY_REVIEW_FILE in" \
        "manifest.env."
elif [ -n "${REVIEW_TEMPLATE_PATH}" ] && [ ! -f "${REVIEW_TEMPLATE_PATH}" ]; then
    fail "SECURITY_REVIEW_TEMPLATE names ${SECURITY_REVIEW_TEMPLATE}, and there is no file there." \
        "The harness compares your review against the template it came from," \
        "so that a copy is not mistaken for a review. Correct the path, or" \
        "empty the key and the comparison is skipped."
elif [ -n "${REVIEW_TEMPLATE_PATH}" ] && cmp -s "${REVIEW_PATH}" "${REVIEW_TEMPLATE_PATH}"; then
    fail "${SECURITY_REVIEW_FILE} is byte for byte the template." \
        "A copy of the template is a copy of the template. Every category needs" \
        "a finding and a disposition written by somebody who read this service," \
        "and this service is not the one the template was written for."
else
    if [ -z "${REVIEW_TEMPLATE_PATH}" ]; then
        pass "${SECURITY_REVIEW_FILE} exists"
        skip "the template comparison: SECURITY_REVIEW_TEMPLATE in manifest.env is empty."
        note "the comparison catches a template committed unchanged. Name the"
        note "file you copied and it runs."
    else
        pass "${SECURITY_REVIEW_FILE} exists and differs from the template"
    fi

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
        note "is a reading of your service, and whether the disposition happened,"
        note "is read by your instructor. Criterion 4 is findings addressed, not"
        note "findings listed."
    else
        fail "The review is incomplete." \
            "Every category needs a finding and a disposition. A category that" \
            "does not apply to your service is dispositioned as out of scope" \
            "with the reason, not deleted. A finding of none needs a sentence" \
            "saying what you checked and how you know, and" \
            "${SECURITY_REVIEW_NONE_MIN_WORDS} words is what counts as a sentence here."
        printf '%s\n' "${REVIEW_PROBLEMS#$'\n'}"
        printf '        %s\n' \
            "The rows are read as a markdown table: category, in scope, finding," \
            "disposition. A row the harness cannot find is usually a category" \
            "identifier that has been edited, or a row split across two lines." \
            "SECURITY_REVIEW_CATEGORIES in manifest.env is the list it looks for."
    fi
fi

# --- the quality gate ------------------------------------------------------------

section 'The SonarQube gate'

skip "the quality gate: this harness does not run SonarQube and cannot read its result."
note "criterion 5 is the gate passing on the new service, on the same terms as"
note "Sprint 7. Bring the result to the review with the project key and the"
note "analysis date, and be ready to talk about anything marked as won't fix."
note "Run it during the week. A gate run once, on Friday, against a week of code"
note "produces a list nobody has time to act on."

# --- live mode -------------------------------------------------------------------

if [ "${LIVE}" -eq 1 ]; then

    command -v curl >/dev/null 2>&1 || abort \
        "curl is not on your PATH, and live mode probes your service with it."

    SERVICE_URL="http://${SERVICE_HOST}:${SERVICE_PORT}"
    AUTH_URL="http://${AUTH_HOST}:${AUTH_PORT}"

    RESP_BODY="$(mktemp)"
    trap 'rm -f "${RESP_BODY}"' EXIT

    HTTP_STATUS=""
    HTTP_BODY=""

    request() {
        req_method="$1"
        req_url="$2"
        req_token="$3"
        req_body="$4"

        req_args=(-s -o "${RESP_BODY}" -w '%{http_code}' --max-time 20
            -X "${req_method}" "${req_url}")
        [ -n "${req_token}" ] && req_args+=(-H "Authorization: Bearer ${req_token}")
        if [ -n "${req_body}" ]; then
            req_args+=(-H 'Content-Type: application/json' --data "${req_body}")
        fi

        if req_result="$(curl "${req_args[@]}" 2>/dev/null)"; then
            HTTP_STATUS="${req_result}"
        else
            HTTP_STATUS="000"
        fi
        HTTP_BODY="$(tr -d '\r\n' <"${RESP_BODY}")"
    }

    json_string() {
        printf '%s' "$1" | sed -n "s/.*\"$2\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -n 1
    }

    has_field() {
        printf '%s' "$1" | grep -q "\"$2\"[[:space:]]*:"
    }

    b64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }

    # A well-formed token signed with a key the platform has never used. Every
    # part of it is right except the one part that makes it trustworthy.
    mint_forged_token() {
        forge_secret="$(openssl rand -hex 32)"
        forge_now="$(date +%s)"
        forge_iss=""
        [ -n "${TOKEN_ISSUER}" ] && forge_iss=",\"iss\":\"${TOKEN_ISSUER}\""
        forge_header="$(printf '%s' '{"alg":"HS256","typ":"JWT"}' | b64url)"
        forge_payload="$(printf \
            '{"sub":"%s","accountId":%s,"roles":["CUSTOMER"],"iat":%s,"exp":%s%s}' \
            "${DEMO_USERNAME}" "${DEMO_ACCOUNT_ID}" "${forge_now}" \
            "$((forge_now + 900))" "${forge_iss}" | b64url)"
        forge_signature="$(printf '%s' "${forge_header}.${forge_payload}" \
            | openssl dgst -sha256 -hmac "${forge_secret}" -binary | b64url)"
        printf '%s.%s.%s' "${forge_header}" "${forge_payload}" "${forge_signature}"
    }

    section 'Live: reaching the service'

    request GET "${SERVICE_URL}${HEALTH_PATH}" "" ""
    if [ "${HTTP_STATUS}" = "000" ]; then
        abort "Nothing answered at ${SERVICE_URL}${HEALTH_PATH}." \
            "Live mode needs your service running, and it starts nothing" \
            "itself. Start it, in the compose stack or on its own, and run this" \
            "again. If it listens elsewhere, correct SERVICE_HOST, SERVICE_PORT" \
            "and HEALTH_PATH in manifest.env."
    elif [ "${HTTP_STATUS}" = "200" ]; then
        pass "the health endpoint answers at ${SERVICE_URL}${HEALTH_PATH}"
        if [ -n "${HTTP_BODY}" ]; then
            note "body: ${HTTP_BODY}"
        else
            note "the body is empty. A health endpoint that says nothing about"
            note "its dependencies answers whether the process is up and nothing"
            note "else, which is the smaller half of the question."
        fi
    elif [ "${HTTP_STATUS}" = "401" ] || [ "${HTTP_STATUS}" = "403" ]; then
        fail "${HEALTH_PATH} answered HTTP ${HTTP_STATUS}, which means it wants a credential." \
            "A liveness route that needs a token cannot be used by Docker, by a" \
            "load balancer, or by anybody debugging the stack at the review." \
            "Exempt it from authentication."
    else
        fail "${HEALTH_PATH} answered HTTP ${HTTP_STATUS}." \
            "Body: ${HTTP_BODY:-empty}" \
            "Something is listening and it did not report itself healthy."
    fi

    section 'Live: the protected route'

    PROBE_URL="${SERVICE_URL}${PROTECTED_PATH}"

    request GET "${PROBE_URL}" "" ""
    if [ "${HTTP_STATUS}" = "401" ]; then
        pass "GET ${PROTECTED_PATH} with no token is refused with HTTP 401"
        ERROR_CODE="$(json_string "${HTTP_BODY}" errorCode)"
        if [ "${ERROR_CODE}" = "AUTH-401" ]; then
            pass "the refusal carries the platform error code AUTH-401"
        elif [ -n "${ERROR_CODE}" ]; then
            fail "The refusal carries errorCode ${ERROR_CODE}, and the platform catalogue uses AUTH-401." \
                "Body: ${HTTP_BODY}" \
                "The Angular error mapping written in Sprint 9 branches on the" \
                "code. A service that invents its own code for a case the" \
                "catalogue already covers renders as an unknown error."
        else
            note "no errorCode in the body: ${HTTP_BODY:-empty}"
            note "the platform envelope is {errorCode, message}, and a client"
            note "that cannot read a code cannot tell an expired session from a"
            note "refused one. Framework-generated 401 bodies usually look like"
            note "this."
        fi
    elif [ "${HTTP_STATUS}" = "000" ]; then
        fail "No response from ${PROBE_URL}." \
            "The health endpoint answered and this route did not."
    else
        fail "GET ${PROTECTED_PATH} with no Authorization header answered HTTP ${HTTP_STATUS}." \
            "Body: ${HTTP_BODY:-empty}" \
            "Criterion 2. Every route on this service except the health check" \
            "requires a verified token. If this route is genuinely public, name" \
            "a protected one in PROTECTED_PATH in manifest.env instead."
    fi

    if command -v openssl >/dev/null 2>&1; then
        FORGED_TOKEN="$(mint_forged_token)"
        request GET "${PROBE_URL}" "${FORGED_TOKEN}" ""
        if [ "${HTTP_STATUS}" = "401" ]; then
            pass "a token signed with a key nobody holds is refused with HTTP 401"
        else
            fail "GET ${PROTECTED_PATH} answered HTTP ${HTTP_STATUS} to a token signed with a random secret." \
                "Body: ${HTTP_BODY:-empty}" \
                "Everything about that token is well formed: the header names" \
                "HS256, the claims are the platform's, the expiry is in the" \
                "future. The only thing wrong with it is the signature." \
                "Accepting it means the signature is not being checked, or is" \
                "being checked after the payload has been read and trusted." \
                "Anyone can mint that token. The harness did it in one line of" \
                "shell."
        fi
    else
        skip "the forged-token probe: openssl is not on your PATH."
        note "the probe mints a well-formed token signed with a random secret and"
        note "expects your service to refuse it. Install openssl and it runs."
    fi

    section 'Live: a real token'

    if [ "${LOGIN_THROTTLE_COOLDOWN_SECONDS}" -gt 0 ]; then
        note "waiting ${LOGIN_THROTTLE_COOLDOWN_SECONDS}s for your login throttle window to empty"
        sleep "${LOGIN_THROTTLE_COOLDOWN_SECONDS}"
    fi

    ACCESS_TOKEN=""
    request POST "${AUTH_URL}${AUTH_LOGIN_PATH}" "" \
        "$(printf '{"username":"%s","password":"%s"}' "${DEMO_USERNAME}" "${DEMO_PASSWORD}")"
    if [ "${HTTP_STATUS}" = "000" ]; then
        skip "the valid-token probes: nothing answered at ${AUTH_URL}${AUTH_LOGIN_PATH}."
        note "the harness does not hold your signing secret and will not mint a"
        note "token your service trusts. It signs in the way the Angular"
        note "application signs in. Start your Auth service, or correct AUTH_HOST"
        note "and AUTH_PORT in manifest.env."
    elif [ "${HTTP_STATUS}" != "200" ]; then
        skip "the valid-token probes: signing in as ${DEMO_USERNAME} answered HTTP ${HTTP_STATUS}."
        note "body: ${HTTP_BODY:-empty}"
        note "seed the demo users, or correct DEMO_USERNAME and DEMO_PASSWORD in"
        note "manifest.env to name a user your Auth service can authenticate."
    else
        ACCESS_TOKEN="$(json_string "${HTTP_BODY}" accessToken)"
        if [ -z "${ACCESS_TOKEN}" ]; then
            skip "the valid-token probes: the sign-in returned no accessToken."
            note "body: ${HTTP_BODY:-empty}"
            note "contracts/auth-api.yaml names the field accessToken."
        else
            pass "signed in as ${DEMO_USERNAME} against ${AUTH_URL}"
        fi
    fi

    if [ -n "${ACCESS_TOKEN}" ]; then
        request GET "${PROBE_URL}" "${ACCESS_TOKEN}" ""
        case "${HTTP_STATUS}" in
            2*)
                pass "GET ${PROTECTED_PATH} with a real token answers HTTP ${HTTP_STATUS}"
                ;;
            401)
                fail "GET ${PROTECTED_PATH} refused a token your own Auth service issued." \
                    "Body: ${HTTP_BODY:-empty}" \
                    "Criterion 2 is that this service authenticates with the" \
                    "platform JWT. A 401 here is one of three things: the two" \
                    "services hold different signing secrets, this service pins" \
                    "an issuer the token does not name, or it reads a claim by a" \
                    "name the contract does not use." \
                    "Decode the token and compare it against" \
                    "contracts/auth-api.yaml."
                ;;
            403)
                fail "GET ${PROTECTED_PATH} answered 403 to ${DEMO_USERNAME}'s own token." \
                    "Body: ${HTTP_BODY:-empty}" \
                    "The token is accepted and the authorisation check refuses" \
                    "it. Either PROTECTED_PATH names a resource belonging to" \
                    "another account, in which case correct it, or the check is" \
                    "comparing the wrong claim."
                ;;
            *)
                fail "GET ${PROTECTED_PATH} answered HTTP ${HTTP_STATUS} to a valid token." \
                    "Body: ${HTTP_BODY:-empty}"
                ;;
        esac
    fi

    note "one account is all this probes. Whether a valid token for one customer"
    note "can reach another customer's data is the finding this sprint's review"
    note "exists to catch, and it is demonstrated to your instructor with two"
    note "accounts rather than asserted here."

    section 'Live: the contract'

    if [ "${EXTENSION}" != "portfolio-pnl" ]; then
        skip "the contract-shape probes: they apply to portfolio-pnl only."
        note "the API for ${EXTENSION} is your team's design. Bring your OpenAPI"
        note "document to the review, served by the running service, and the"
        note "Angular client generated from it."
    elif [ -z "${ACCESS_TOKEN}" ]; then
        skip "the contract-shape probes: they need the token the sign-in did not produce."
    else
        if [ -n "${CONTRACT_FILE}" ] && [ ! -f "${SPRINT_DIR}/${CONTRACT_FILE}" ]; then
            note "CONTRACT_FILE names ${CONTRACT_FILE} and there is no file there."
            note "The probes below carry the contract's field names themselves,"
            note "so they still run, but correct the path: the contract is what"
            note "you build against."
        fi

        SUMMARY_FIELDS="accountId baseCurrency cashBalance marketValue costBasis
unrealisedPnl realisedPnl totalValue positionCount partial asOf"
        POSITION_FIELDS="accountId symbol quantity averageCost costBasis currency stale"

        check_shape() {
            shape_label="$1"
            shape_fields="$2"
            shape_body="$3"

            shape_missing=""
            for field in ${shape_fields}; do
                has_field "${shape_body}" "${field}" || shape_missing="${shape_missing} ${field}"
            done

            if [ -z "${shape_missing}" ]; then
                pass "${shape_label}: every field the contract requires is present"
            else
                fail "${shape_label}: fields the contract requires are missing:${shape_missing}" \
                    "Body: ${shape_body:-empty}" \
                    "Every schema in portfolio-api.yaml sets" \
                    "additionalProperties: false and lists its required fields." \
                    "The Angular client is generated from that document, so a" \
                    "missing or renamed field is a compile error there."
            fi
        }

        SUMMARY_PATH="/api/v1/portfolio/${DEMO_ACCOUNT_ID}"
        request GET "${SERVICE_URL}${SUMMARY_PATH}" "${ACCESS_TOKEN}" ""
        if [ "${HTTP_STATUS}" = "200" ]; then
            check_shape "GET ${SUMMARY_PATH}" "${SUMMARY_FIELDS}" "${HTTP_BODY}"
        elif [ "${HTTP_STATUS}" = "503" ]; then
            skip "the summary shape: the service answered 503, pricing unavailable."
            note "body: ${HTTP_BODY:-empty}"
            note "that is a contract answer, not a defect, and it is what the"
            note "contract asks for when no held instrument can be priced. Check"
            note "your Fauxnance key and your remaining quota, then run again."
        else
            fail "GET ${SUMMARY_PATH} answered HTTP ${HTTP_STATUS}." \
                "Body: ${HTTP_BODY:-empty}" \
                "The contract answers 200 with a PortfolioSummary for an account" \
                "the token may reach."
        fi

        POSITIONS_PATH="/api/v1/portfolio/${DEMO_ACCOUNT_ID}/positions"
        request GET "${SERVICE_URL}${POSITIONS_PATH}" "${ACCESS_TOKEN}" ""
        if [ "${HTTP_STATUS}" != "200" ]; then
            if [ "${HTTP_STATUS}" = "503" ]; then
                skip "the positions shape: the service answered 503, pricing unavailable."
                note "as above: a contract answer rather than a defect."
            else
                fail "GET ${POSITIONS_PATH} answered HTTP ${HTTP_STATUS}." \
                    "Body: ${HTTP_BODY:-empty}" \
                    "The contract answers 200 with an array of PricedPosition."
            fi
        else
            case "${HTTP_BODY}" in
                \[*)
                    STRIPPED="$(printf '%s' "${HTTP_BODY}" | tr -d '[] ')"
                    if [ -z "${STRIPPED}" ]; then
                        skip "the positions shape: account ${DEMO_ACCOUNT_ID} holds nothing, so the array is empty."
                        note "an empty array is a correct answer and it proves"
                        note "nothing about the shape. Fill an order for this"
                        note "account and run again, which is worth doing before"
                        note "the demonstration anyway."
                    else
                        check_shape "GET ${POSITIONS_PATH}" "${POSITION_FIELDS}" "${HTTP_BODY}"
                        note "the fields are read across the whole array, so one"
                        note "position carrying them all satisfies this. Whether"
                        note "every position carries them is read at the review."
                    fi
                    ;;
                *)
                    fail "GET ${POSITIONS_PATH} did not answer with a JSON array." \
                        "Body: ${HTTP_BODY:-empty}" \
                        "The contract types this response as an array of" \
                        "PricedPosition, not as an object wrapping one."
                    ;;
            esac
        fi

        note "two of the three contract routes are probed here. The profit and"
        note "loss route, its date bounds and the staleness markers are read at"
        note "the review, against the contract."
    fi
fi

# --- result ------------------------------------------------------------------------

printf '\n%s\n' '----------------------------------------------------------------'
printf '%s passed, %s failed\n' "${PASSED}" "${FAILED}"

if [ "${FAILED}" -eq 0 ]; then
    if [ "${LIVE}" -eq 0 ]; then
        printf '\nThe harness is satisfied by the static checks. It has read your\n'
        printf 'manifest, counted your decision log entries and read your security\n'
        printf 'review, and it has not sent a single request. Run it again with\n'
        printf '%s\n' '--live once your stack is up.'
    else
        printf '\nThe harness is satisfied. It has called your health endpoint, been\n'
        printf 'refused twice and admitted once, without knowing whether the data\n'
        printf 'behind that answer was live or seeded.\n'
    fi
    printf '\nMost of this sprint is assessed by a person. Whether the scope agreed\n'
    printf 'on Monday is the scope delivered, whether the log records decisions or\n'
    printf 'events, whether the review is a reading of your service, whether the\n'
    printf 'findings were addressed, whether the feature is usable in the Angular\n'
    printf 'application, and whether the demonstration ran on live data are all\n'
    printf 'read at the review.\n'
    exit 0
fi

printf '\nEach failure above says what was expected and where to look. Nothing\n'
printf 'here reads your backlog, your scope agreement or your quality gate, and\n'
printf 'all three are assessed.\n'

exit 1
