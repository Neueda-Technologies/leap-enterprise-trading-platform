#!/usr/bin/env bash
#
# Sprint 10 acceptance harness.
#
#   check.sh              static checks only. No running service.
#   check.sh --live       the static checks, then the probes against your
#                         running stack.
#
# Static mode reads manifest.env, confirms the four briefs are where the harness
# expects them, counts the decision log entries that are not the template, and
# reads the combined security review.
#
# Live mode needs the whole stack up: the four services, your Auth service, and
# Kafka and Postgres behind them. It starts nothing and stops nothing. It signs
# in once, then puts the same four probes to each service: health answers, the
# protected route refuses a missing token, refuses a token signed with a key
# nobody holds, and answers a real one. Then it follows the integration chain as
# far as it can be followed from outside: it writes a preference and reads it
# back, runs the command you declared to publish a trade event and watches for a
# notification record, runs the command you declared to publish a market-data
# quote and watches for a triggered alert and the notification behind it. For the
# portfolio service it also reads two routes from contracts/portfolio-api.yaml
# and checks the shape of the answers.
#
# Both modes read your names from manifest.env, so the harness asserts your
# design rather than dictating one.
#
# Every skip is named. Several things this sprint is assessed on cannot be seen
# from outside a running service: whether the notification went to the channel
# preferences holds rather than to a constant, whether a replayed event produces
# one message or two, whether the alert reached a customer, whether the scope
# agreed on Monday is the scope delivered. Those are demonstrated to your
# instructor.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPRINT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
MANIFEST="${SPRINT_DIR}/manifest.env"

# The four mandatory extensions, in the order they are built. The harness reads
# them in this order too, so the output follows the dependency chain.
SERVICES="preferences notifications watchlists portfolio"

# The brief that ships for each, under catalogue/, and the name used in output.
# Both sets are read indirectly, through the service name in the loops below.
# shellcheck disable=SC2034
BRIEF_preferences="customer-preferences.md"
# shellcheck disable=SC2034
BRIEF_notifications="customer-notifications.md"
# shellcheck disable=SC2034
BRIEF_watchlists="watchlists-price-alerts.md"
# shellcheck disable=SC2034
BRIEF_portfolio="portfolio-pnl.md"

# shellcheck disable=SC2034
LABEL_preferences="customer preferences"
# shellcheck disable=SC2034
LABEL_notifications="customer notifications"
# shellcheck disable=SC2034
LABEL_watchlists="watchlists and price alerts"
# shellcheck disable=SC2034
LABEL_portfolio="portfolio and P&L"

LIVE=0
while [ "$#" -gt 0 ]; do
    case "$1" in
        --live) LIVE=1; shift ;;
        -h|--help) sed -n '2,34p' "${BASH_SOURCE[0]}" | sed 's/^#\{1,2\} \{0,1\}//'; exit 0 ;;
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

upper() { printf '%s' "$1" | tr '[:lower:]' '[:upper:]'; }

value_of() {
    eval "printf '%s' \"\${$1:-}\""
}

printf 'Sprint 10 acceptance harness\n'
if [ "${LIVE}" -eq 1 ]; then
    printf 'Static checks, then live probes against your running stack.\n'
else
    printf 'Static checks only. Add --live once the four services are up.\n'
fi

# --- the manifest --------------------------------------------------------------

section 'Manifest'

[ -f "${MANIFEST}" ] || abort \
    "No manifest.env in ${SPRINT_DIR}." \
    "The harness reads your document paths, your four service addresses and the" \
    "names live mode needs from that file. If you have deleted it, restore it" \
    "from the repository."

DECISION_LOG_DIR=""
DECISION_LOG_TEMPLATE=""
DECISION_LOG_MIN_ENTRIES=""
SECURITY_REVIEW_FILE=""
SECURITY_REVIEW_TEMPLATE=""
SECURITY_REVIEW_CATEGORIES=""
SECURITY_REVIEW_NONE_MIN_WORDS=""
SECURITY_REVIEW_SERVICE_NAMES=""
SERVICE_HOST=""
PREFERENCES_PORT=""
# The per-service paths below are read indirectly, through the service name.
# shellcheck disable=SC2034
PREFERENCES_HEALTH_PATH=""
# shellcheck disable=SC2034
PREFERENCES_PROTECTED_PATH=""
NOTIFICATIONS_PORT=""
# shellcheck disable=SC2034
NOTIFICATIONS_HEALTH_PATH=""
# shellcheck disable=SC2034
NOTIFICATIONS_PROTECTED_PATH=""
WATCHLISTS_PORT=""
# shellcheck disable=SC2034
WATCHLISTS_HEALTH_PATH=""
# shellcheck disable=SC2034
WATCHLISTS_PROTECTED_PATH=""
PORTFOLIO_PORT=""
# shellcheck disable=SC2034
PORTFOLIO_HEALTH_PATH=""
# shellcheck disable=SC2034
PORTFOLIO_PROTECTED_PATH=""
AUTH_HOST=""
AUTH_PORT=""
AUTH_LOGIN_PATH=""
DEMO_USERNAME=""
DEMO_PASSWORD=""
DEMO_ACCOUNT_ID=""
TOKEN_ISSUER=""
LOGIN_THROTTLE_COOLDOWN_SECONDS=""
PREF_WRITE_METHOD=""
PREF_WRITE_PATH=""
PREF_WRITE_BODY=""
PREF_READ_PATH=""
PREF_EXPECT_VALUE=""
TRADE_EVENT_PUBLISH_CMD=""
NOTIFICATIONS_HISTORY_PATH=""
NOTIFICATIONS_RECORD_MARKER=""
NOTIFICATION_SETTLE_SECONDS=""
WATCHLIST_ALERT_SETUP_METHOD=""
WATCHLIST_ALERT_SETUP_PATH=""
WATCHLIST_ALERT_SETUP_BODY=""
MARKET_DATA_PUBLISH_CMD=""
WATCHLIST_ALERTS_PATH=""
WATCHLIST_TRIGGERED_MARKER=""
ALERT_SETTLE_SECONDS=""
CONTRACT_FILE=""

# shellcheck source=/dev/null
. "${MANIFEST}"

STATIC_KEYS="DECISION_LOG_DIR DECISION_LOG_TEMPLATE DECISION_LOG_MIN_ENTRIES
SECURITY_REVIEW_FILE SECURITY_REVIEW_CATEGORIES SECURITY_REVIEW_NONE_MIN_WORDS"

LIVE_KEYS="SERVICE_HOST AUTH_HOST AUTH_PORT AUTH_LOGIN_PATH DEMO_USERNAME
DEMO_PASSWORD DEMO_ACCOUNT_ID LOGIN_THROTTLE_COOLDOWN_SECONDS
PREFERENCES_PORT PREFERENCES_HEALTH_PATH PREFERENCES_PROTECTED_PATH
NOTIFICATIONS_PORT NOTIFICATIONS_HEALTH_PATH NOTIFICATIONS_PROTECTED_PATH
WATCHLISTS_PORT WATCHLISTS_HEALTH_PATH WATCHLISTS_PROTECTED_PATH
PORTFOLIO_PORT PORTFOLIO_HEALTH_PATH PORTFOLIO_PROTECTED_PATH"

REQUIRED_KEYS="${STATIC_KEYS}"
[ "${LIVE}" -eq 1 ] && REQUIRED_KEYS="${STATIC_KEYS} ${LIVE_KEYS}"

OUTSTANDING=""
for key in ${REQUIRED_KEYS}; do
    value="$(value_of "${key}")"
    if [ -z "${value}" ] || [ "${value}" = "CHANGE_ME" ]; then
        OUTSTANDING="${OUTSTANDING} ${key}"
    fi
done

if [ -n "${OUTSTANDING}" ]; then
    abort "manifest.env is not filled in." \
        "Still empty or set to CHANGE_ME:${OUTSTANDING}" \
        "Every key in that list ships with a defensible default, so an empty one" \
        "is a value your team deleted rather than one nobody has chosen yet." \
        "The keys that are genuinely yours to fill in are the two publish" \
        "commands and the preference paths, and every one of those is optional:" \
        "leave it empty and the probe it drives becomes a named skip."
fi

for key in DECISION_LOG_MIN_ENTRIES SECURITY_REVIEW_NONE_MIN_WORDS \
    LOGIN_THROTTLE_COOLDOWN_SECONDS NOTIFICATION_SETTLE_SECONDS \
    ALERT_SETTLE_SECONDS PREFERENCES_PORT NOTIFICATIONS_PORT WATCHLISTS_PORT \
    PORTFOLIO_PORT; do
    value="$(value_of "${key}")"
    if [ -n "${value}" ]; then
        printf '%s' "${value}" | grep -qE '^[0-9]+$' || abort \
            "${key} in manifest.env is not a whole number: ${value}"
    fi
done

pass "manifest.env declares every name the harness needs"

# Four services on four ports. Two services on one port is a compose file that
# starts and a stack where one of them is unreachable.
if [ "${LIVE}" -eq 1 ]; then
    PORT_LIST=()
    for service in ${SERVICES}; do
        PORT_LIST+=("$(value_of "$(upper "${service}")_PORT")")
    done
    DISTINCT="$(printf '%s\n' "${PORT_LIST[@]}" | LC_ALL=C sort -u | wc -l | tr -d ' ')"
    if [ "${DISTINCT}" -eq 4 ]; then
        pass "the four services are declared on four different ports"
    else
        fail "Two or more services are declared on the same port: ${PORT_LIST[*]}" \
            "Each service is its own process in its own container with its own" \
            "port, its own folder under services/ and its own entry in" \
            "docker-compose.yml. Correct the ports in manifest.env, or the" \
            "compose file if the collision is real."
    fi
fi

# --- the briefs -----------------------------------------------------------------

section 'The four briefs'

BRIEF_PROBLEMS=""
for service in ${SERVICES}; do
    brief="$(value_of "BRIEF_${service}")"
    if [ ! -f "${SPRINT_DIR}/catalogue/${brief}" ]; then
        BRIEF_PROBLEMS="${BRIEF_PROBLEMS} catalogue/${brief}"
    fi
done

if [ -z "${BRIEF_PROBLEMS}" ]; then
    pass "all four briefs are in catalogue/, in build order"
else
    fail "Briefs missing from ${SPRINT_DIR}/catalogue:${BRIEF_PROBLEMS}" \
        "All four ship with this folder and all four are mandatory this sprint." \
        "Restore them from the repository."
fi

# --- the decision log ------------------------------------------------------------

LOG_DIR_PATH="${SPRINT_DIR}/${DECISION_LOG_DIR}"
LOG_TEMPLATE_PATH="${SPRINT_DIR}/${DECISION_LOG_TEMPLATE}"
REVIEW_PATH="${SPRINT_DIR}/${SECURITY_REVIEW_FILE}"
REVIEW_TEMPLATE_PATH=""
[ -n "${SECURITY_REVIEW_TEMPLATE}" ] && REVIEW_TEMPLATE_PATH="${SPRINT_DIR}/${SECURITY_REVIEW_TEMPLATE}"

section 'The decision log'

if [ ! -d "${LOG_DIR_PATH}" ]; then
    fail "No ${DECISION_LOG_DIR} directory in ${SPRINT_DIR}." \
        "A committed decision log is an acceptance criterion. The folder ships" \
        "with the template in it. Restore it, or correct DECISION_LOG_DIR in" \
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
            "instead. Four services in one week produce more of these decisions" \
            "than one service does, and the ones between services are the ones" \
            "worth writing down."
    fi

    if [ -n "${LOG_PROBLEMS}" ]; then
        printf '        %s\n' "Files in ${DECISION_LOG_DIR} that were not counted:"
        printf '%s\n' "${LOG_PROBLEMS#$'\n'}"
    fi
fi

# --- the security review ---------------------------------------------------------

section 'The combined OWASP review'

if [ ! -f "${REVIEW_PATH}" ]; then
    fail "No ${SECURITY_REVIEW_FILE} in ${SPRINT_DIR}." \
        "One review across the four services, with its findings addressed, is" \
        "an acceptance criterion. Copy the Sprint 8 template into this folder" \
        "and fill it in as you build:" \
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
        "a finding and a disposition written by somebody who read these four" \
        "services, and they are not the service the template was written for."
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
        note "is a reading of your services, and whether the disposition"
        note "happened, is read by your instructor. The criterion is findings"
        note "addressed, not findings listed."
    else
        fail "The review is incomplete." \
            "Every category needs a finding and a disposition. A category that" \
            "applies to none of the four services is dispositioned as out of" \
            "scope with the reason, not deleted. A finding of none needs a" \
            "sentence saying what you checked and how you know, and" \
            "${SECURITY_REVIEW_NONE_MIN_WORDS} words is what counts as a sentence here."
        printf '%s\n' "${REVIEW_PROBLEMS#$'\n'}"
        printf '        %s\n' \
            "The rows are read as a markdown table: category, in scope, finding," \
            "disposition. A row the harness cannot find is usually a category" \
            "identifier that has been edited, or a row split across two lines." \
            "SECURITY_REVIEW_CATEGORIES in manifest.env is the list it looks for."
    fi

    if [ -n "${SECURITY_REVIEW_SERVICE_NAMES}" ]; then
        UNMENTIONED=""
        for name in ${SECURITY_REVIEW_SERVICE_NAMES}; do
            grep -qi -- "${name}" "${REVIEW_PATH}" || UNMENTIONED="${UNMENTIONED} ${name}"
        done
        if [ -z "${UNMENTIONED}" ]; then
            pass "the review names all four services"
            note "one review across four services is the criterion, and it is not"
            note "four reviews concatenated either. The rows worth reading are"
            note "the ones where a category lands differently on one service than"
            note "on another."
        else
            fail "The review never names:${UNMENTIONED}" \
                "One combined review has to say something about each of the four" \
                "services. A service that appears nowhere in it was either not" \
                "reviewed or is called something else here: correct the names in" \
                "SECURITY_REVIEW_SERVICE_NAMES in manifest.env if it is the" \
                "second."
        fi
    else
        skip "the per-service mention check: SECURITY_REVIEW_SERVICE_NAMES is empty."
        note "it searches your review for each service by name, so that a review"
        note "covering three of the four is visible as one."
    fi
fi

# --- live mode -------------------------------------------------------------------

if [ "${LIVE}" -eq 1 ]; then

    command -v curl >/dev/null 2>&1 || abort \
        "curl is not on your PATH, and live mode probes your services with it."

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

    # How many times a field name appears in a response body. One notification
    # record carries the field once, so the count is the record count.
    count_field() {
        # grep exits non-zero on no match, and an empty history is a legitimate
        # starting state, so the failure is swallowed and the count is zero.
        printf '%s' "$1" | { grep -o "\"$2\"" || true; } | wc -l | tr -d ' '
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

    # A command the team declared, run in a shell from this folder. The harness
    # has no Kafka client of its own and will not guess at your topic
    # configuration, your container names or your envelope.
    run_declared() {
        run_label="$1"
        run_cmd="$2"
        if run_output="$(cd "${SPRINT_DIR}" && bash -c "${run_cmd}" 2>&1)"; then
            pass "${run_label} ran and exited 0"
            [ -n "${run_output}" ] && note "output: $(printf '%s' "${run_output}" | tr '\n' ' ' | cut -c1-160)"
            return 0
        fi
        fail "${run_label} exited non-zero." \
            "Output: $(printf '%s' "${run_output:-empty}" | tr '\n' ' ' | cut -c1-200)" \
            "The harness runs the command exactly as you wrote it, in a shell," \
            "from ${SPRINT_DIR}. Run it by hand and fix it there first."
        return 1
    }

    section 'Live: signing in'

    if [ "${LOGIN_THROTTLE_COOLDOWN_SECONDS}" -gt 0 ]; then
        note "waiting ${LOGIN_THROTTLE_COOLDOWN_SECONDS}s for your login throttle window to empty"
        sleep "${LOGIN_THROTTLE_COOLDOWN_SECONDS}"
    fi

    ACCESS_TOKEN=""
    request POST "${AUTH_URL}${AUTH_LOGIN_PATH}" "" \
        "$(printf '{"username":"%s","password":"%s"}' "${DEMO_USERNAME}" "${DEMO_PASSWORD}")"
    if [ "${HTTP_STATUS}" = "000" ]; then
        skip "every valid-token probe: nothing answered at ${AUTH_URL}${AUTH_LOGIN_PATH}."
        note "the harness does not hold your signing secret and will not mint a"
        note "token your services trust. It signs in the way the Angular"
        note "application signs in. Start your Auth service, or correct AUTH_HOST"
        note "and AUTH_PORT in manifest.env."
    elif [ "${HTTP_STATUS}" != "200" ]; then
        skip "every valid-token probe: signing in as ${DEMO_USERNAME} answered HTTP ${HTTP_STATUS}."
        note "body: ${HTTP_BODY:-empty}"
        note "seed the demo users, or correct DEMO_USERNAME and DEMO_PASSWORD in"
        note "manifest.env to name a user your Auth service can authenticate."
    else
        ACCESS_TOKEN="$(json_string "${HTTP_BODY}" accessToken)"
        if [ -z "${ACCESS_TOKEN}" ]; then
            skip "every valid-token probe: the sign-in returned no accessToken."
            note "body: ${HTTP_BODY:-empty}"
            note "contracts/auth-api.yaml names the field accessToken."
        else
            pass "signed in as ${DEMO_USERNAME} against ${AUTH_URL}"
            note "one token, four services. Each of them verifies it on its own."
        fi
    fi

    FORGED_TOKEN=""
    if command -v openssl >/dev/null 2>&1; then
        FORGED_TOKEN="$(mint_forged_token)"
    else
        skip "every forged-token probe: openssl is not on your PATH."
        note "the probe mints a well-formed token signed with a random secret and"
        note "expects each service to refuse it. Install openssl and it runs."
    fi

    # --- the same four probes, once per service ---------------------------------

    REACHABLE=""

    for service in ${SERVICES}; do
        UP="$(upper "${service}")"
        label="$(value_of "LABEL_${service}")"
        port="$(value_of "${UP}_PORT")"
        health_path="$(value_of "${UP}_HEALTH_PATH")"
        protected_path="$(value_of "${UP}_PROTECTED_PATH")"
        base_url="http://${SERVICE_HOST}:${port}"

        section "Live: ${label}, on ${port}"

        request GET "${base_url}${health_path}" "" ""
        if [ "${HTTP_STATUS}" = "000" ]; then
            fail "Nothing answered at ${base_url}${health_path}." \
                "All four services are mandatory this sprint and live mode" \
                "starts none of them. Start it, in the compose stack or on its" \
                "own, and run this again. If it listens elsewhere, correct" \
                "${UP}_PORT and ${UP}_HEALTH_PATH in manifest.env." \
                "The remaining probes for this service are skipped."
            continue
        elif [ "${HTTP_STATUS}" = "200" ]; then
            pass "the health endpoint answers at ${base_url}${health_path}"
            if [ -z "${HTTP_BODY}" ]; then
                note "the body is empty. A health endpoint that says nothing about"
                note "its dependencies answers whether the process is up and"
                note "nothing else, which is the smaller half of the question."
            fi
        elif [ "${HTTP_STATUS}" = "401" ] || [ "${HTTP_STATUS}" = "403" ]; then
            fail "${health_path} answered HTTP ${HTTP_STATUS}, which means it wants a credential." \
                "A liveness route that needs a token cannot be used by Docker, by" \
                "a load balancer, or by anybody debugging the stack at the" \
                "review. Exempt it from authentication."
        else
            fail "${health_path} answered HTTP ${HTTP_STATUS}." \
                "Body: ${HTTP_BODY:-empty}" \
                "Something is listening and it did not report itself healthy."
        fi

        REACHABLE="${REACHABLE} ${service}"
        probe_url="${base_url}${protected_path}"

        request GET "${probe_url}" "" ""
        if [ "${HTTP_STATUS}" = "401" ]; then
            pass "GET ${protected_path} with no token is refused with HTTP 401"
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
                note "that cannot read a code cannot tell an expired session from"
                note "a refused one. Framework-generated 401 bodies usually look"
                note "like this."
            fi
        elif [ "${HTTP_STATUS}" = "000" ]; then
            fail "No response from ${probe_url}." \
                "The health endpoint answered and this route did not."
        else
            fail "GET ${protected_path} with no Authorization header answered HTTP ${HTTP_STATUS}." \
                "Body: ${HTTP_BODY:-empty}" \
                "Every route on every one of the four services, except the health" \
                "check, requires a verified token. If this route is genuinely" \
                "public, name a protected one in ${UP}_PROTECTED_PATH in" \
                "manifest.env instead."
        fi

        if [ -n "${FORGED_TOKEN}" ]; then
            request GET "${probe_url}" "${FORGED_TOKEN}" ""
            if [ "${HTTP_STATUS}" = "401" ]; then
                pass "a token signed with a key nobody holds is refused with HTTP 401"
            else
                fail "GET ${protected_path} answered HTTP ${HTTP_STATUS} to a token signed with a random secret." \
                    "Body: ${HTTP_BODY:-empty}" \
                    "Everything about that token is well formed: the header names" \
                    "HS256, the claims are the platform's, the expiry is in the" \
                    "future. The only thing wrong with it is the signature." \
                    "Accepting it means this service is not checking the" \
                    "signature, or is reading the payload before checking it." \
                    "Four services verify the platform token this week, so this" \
                    "is four chances to leave the check out of one of them."
            fi
        fi

        if [ -n "${ACCESS_TOKEN}" ]; then
            request GET "${probe_url}" "${ACCESS_TOKEN}" ""
            case "${HTTP_STATUS}" in
                2*)
                    pass "GET ${protected_path} with a real token answers HTTP ${HTTP_STATUS}"
                    ;;
                401)
                    fail "GET ${protected_path} refused a token your own Auth service issued." \
                        "Body: ${HTTP_BODY:-empty}" \
                        "A 401 here is one of three things: this service and the" \
                        "Auth service hold different signing secrets, this" \
                        "service pins an issuer the token does not name, or it" \
                        "reads a claim by a name the contract does not use." \
                        "Decode the token and compare it against" \
                        "contracts/auth-api.yaml."
                    ;;
                403)
                    fail "GET ${protected_path} answered 403 to ${DEMO_USERNAME}'s own token." \
                        "Body: ${HTTP_BODY:-empty}" \
                        "The token is accepted and the authorisation check refuses" \
                        "it. Either ${UP}_PROTECTED_PATH names a resource" \
                        "belonging to another account, in which case correct it," \
                        "or the check is comparing the wrong claim."
                    ;;
                *)
                    fail "GET ${protected_path} answered HTTP ${HTTP_STATUS} to a valid token." \
                        "Body: ${HTTP_BODY:-empty}"
                    ;;
            esac
        fi
    done

    note "one account is all this probes, on all four services. Whether a valid"
    note "token for one customer can reach another customer's preferences,"
    note "notifications, watchlist or portfolio is what the combined review"
    note "exists to catch, and it is demonstrated with two accounts rather than"
    note "asserted here."

    service_reachable() {
        case " ${REACHABLE} " in
            *" $1 "*) return 0 ;;
            *) return 1 ;;
        esac
    }

    # --- the chain, first link: a preference written and read back ---------------

    section 'Live: the preference round trip'

    PREF_URL="http://${SERVICE_HOST}:${PREFERENCES_PORT}"

    if ! service_reachable preferences; then
        skip "the preference round trip: the preferences service did not answer."
    elif [ -z "${ACCESS_TOKEN}" ]; then
        skip "the preference round trip: it needs the token the sign-in did not produce."
    elif [ -z "${PREF_WRITE_PATH}" ] || [ -z "${PREF_READ_PATH}" ] || [ -z "${PREF_EXPECT_VALUE}" ]; then
        skip "the preference round trip: PREF_WRITE_PATH, PREF_READ_PATH or PREF_EXPECT_VALUE is empty."
        note "set the three and the harness writes a channel through your API and"
        note "reads it back on the route notifications calls. Until then the"
        note "round trip is read at the review."
    else
        request GET "${PREF_URL}${PREF_READ_PATH}" "${ACCESS_TOKEN}" ""
        BEFORE_BODY="${HTTP_BODY}"
        if [ "${HTTP_STATUS}" = "200" ] && printf '%s' "${BEFORE_BODY}" | grep -q -- "${PREF_EXPECT_VALUE}"; then
            note "${PREF_EXPECT_VALUE} is already the stored value, so the"
            note "read-back below proves the write path did not break it rather"
            note "than proving it changed it. Alternate PREF_EXPECT_VALUE between"
            note "runs if you want the stronger result."
        fi

        request "${PREF_WRITE_METHOD:-PUT}" "${PREF_URL}${PREF_WRITE_PATH}" \
            "${ACCESS_TOKEN}" "${PREF_WRITE_BODY}"
        case "${HTTP_STATUS}" in
            2*)
                pass "${PREF_WRITE_METHOD:-PUT} ${PREF_WRITE_PATH} accepted the preference, HTTP ${HTTP_STATUS}"

                request GET "${PREF_URL}${PREF_READ_PATH}" "${ACCESS_TOKEN}" ""
                if [ "${HTTP_STATUS}" != "200" ]; then
                    fail "GET ${PREF_READ_PATH} answered HTTP ${HTTP_STATUS} after the write." \
                        "Body: ${HTTP_BODY:-empty}" \
                        "The write was accepted and the read that follows it did" \
                        "not answer. A preference nothing can read is a preference" \
                        "notifications cannot resolve."
                elif printf '%s' "${HTTP_BODY}" | grep -q -- "${PREF_EXPECT_VALUE}"; then
                    pass "the read-back carries ${PREF_EXPECT_VALUE}, so the write and read paths agree"
                    note "this is a round trip through one process. Whether the"
                    note "value survives a restart, and whether the customer's"
                    note "next sign-in picks up the default account, are"
                    note "demonstrated at the review."
                else
                    fail "GET ${PREF_READ_PATH} does not carry ${PREF_EXPECT_VALUE} after the write." \
                        "Body: ${HTTP_BODY:-empty}" \
                        "Either the write did not persist, or the read route" \
                        "serves something the write route does not update. Both" \
                        "are the same defect from the notifications service's" \
                        "point of view: it asks for a channel and gets the wrong" \
                        "one." \
                        "If your read-back renders the channel under a different" \
                        "spelling, correct PREF_EXPECT_VALUE in manifest.env."
                fi
                ;;
            401|403)
                fail "${PREF_WRITE_METHOD:-PUT} ${PREF_WRITE_PATH} answered HTTP ${HTTP_STATUS} to ${DEMO_USERNAME}'s own token." \
                    "Body: ${HTTP_BODY:-empty}" \
                    "A customer sets their own preferences. Check the account in" \
                    "the path against DEMO_ACCOUNT_ID."
                ;;
            *)
                fail "${PREF_WRITE_METHOD:-PUT} ${PREF_WRITE_PATH} answered HTTP ${HTTP_STATUS}." \
                    "Body: ${HTTP_BODY:-empty}" \
                    "The body sent was: ${PREF_WRITE_BODY:-empty}" \
                    "Correct PREF_WRITE_METHOD, PREF_WRITE_PATH and" \
                    "PREF_WRITE_BODY in manifest.env to match the API your team" \
                    "designed. The harness sends what you declared and nothing" \
                    "else."
                ;;
        esac
    fi

    # --- second link: a trade event becomes a notification ----------------------

    section 'Live: a trade event becomes a notification'

    NOTIF_URL="http://${SERVICE_HOST}:${NOTIFICATIONS_PORT}"
    NOTIF_MARKER="${NOTIFICATIONS_RECORD_MARKER:-notificationId}"
    NOTIF_COUNT_BEFORE=""

    # Prints the number of records in the demo account's notification history,
    # or returns non-zero when the history cannot be read at all.
    notification_count() {
        if ! service_reachable notifications || [ -z "${ACCESS_TOKEN}" ] \
            || [ -z "${NOTIFICATIONS_HISTORY_PATH}" ]; then
            return 1
        fi
        request GET "${NOTIF_URL}${NOTIFICATIONS_HISTORY_PATH}" "${ACCESS_TOKEN}" ""
        [ "${HTTP_STATUS}" = "200" ] || return 1
        count_field "${HTTP_BODY}" "${NOTIF_MARKER}"
    }

    if ! service_reachable notifications; then
        skip "the trade-event probe: the notifications service did not answer."
    elif [ -z "${ACCESS_TOKEN}" ]; then
        skip "the trade-event probe: it needs the token the sign-in did not produce."
    elif [ -z "${TRADE_EVENT_PUBLISH_CMD}" ]; then
        skip "the trade-event probe: TRADE_EVENT_PUBLISH_CMD in manifest.env is empty."
        note "the harness has no Kafka client. Declare one command that puts a"
        note "single ORDER_FILLED event for account ${DEMO_ACCOUNT_ID} onto"
        note "trade-events and it watches your notification history grow. Until"
        note "then, consumption is demonstrated at the review, with the message"
        note "published in front of your instructor."
    elif [ -z "${NOTIFICATIONS_HISTORY_PATH}" ]; then
        skip "the trade-event probe: NOTIFICATIONS_HISTORY_PATH in manifest.env is empty."
        note "the probe counts records before and after, so it needs the route a"
        note "customer reads their notifications on."
    else
        request GET "${NOTIF_URL}${NOTIFICATIONS_HISTORY_PATH}" "${ACCESS_TOKEN}" ""
        if [ "${HTTP_STATUS}" != "200" ]; then
            fail "GET ${NOTIFICATIONS_HISTORY_PATH} answered HTTP ${HTTP_STATUS} before anything was published." \
                "Body: ${HTTP_BODY:-empty}" \
                "The probe reads this route twice and compares. It cannot start."
        else
            NOTIF_COUNT_BEFORE="$(count_field "${HTTP_BODY}" "${NOTIF_MARKER}")"
            note "${NOTIF_COUNT_BEFORE} record(s) in the history now, counted by \"${NOTIF_MARKER}\""

            if run_declared "TRADE_EVENT_PUBLISH_CMD" "${TRADE_EVENT_PUBLISH_CMD}"; then
                note "waiting ${NOTIFICATION_SETTLE_SECONDS:-15}s for the consumer, the channel lookup and the delivery"
                sleep "${NOTIFICATION_SETTLE_SECONDS:-15}"

                request GET "${NOTIF_URL}${NOTIFICATIONS_HISTORY_PATH}" "${ACCESS_TOKEN}" ""
                NOTIF_COUNT_AFTER="$(count_field "${HTTP_BODY}" "${NOTIF_MARKER}")"
                if [ "${HTTP_STATUS}" = "200" ] && [ "${NOTIF_COUNT_AFTER}" -gt "${NOTIF_COUNT_BEFORE}" ]; then
                    pass "the history grew from ${NOTIF_COUNT_BEFORE} to ${NOTIF_COUNT_AFTER} records after the event"
                    note "a record appeared. Which channel it went out on, whether"
                    note "that channel came from the preferences service or from a"
                    note "constant, and whether a replay of the same event produces"
                    note "a second message are all read at the review."
                else
                    fail "The history holds ${NOTIF_COUNT_AFTER} record(s), and it held ${NOTIF_COUNT_BEFORE} before the event." \
                        "Status: ${HTTP_STATUS}. Body: ${HTTP_BODY:-empty}" \
                        "Four things produce this: the event never reached the" \
                        "topic, the consumer is not running or sits in a group" \
                        "whose offsets are already past it, the channel lookup" \
                        "against preferences failed and the message was dropped" \
                        "rather than recorded, or the record exists and this route" \
                        "does not show it." \
                        "Read your consumer log first. If the consumer needs" \
                        "longer than ${NOTIFICATION_SETTLE_SECONDS:-15}s, raise" \
                        "NOTIFICATION_SETTLE_SECONDS in manifest.env." \
                        "If your records carry a field other than" \
                        "\"${NOTIF_MARKER}\", correct NOTIFICATIONS_RECORD_MARKER."
                fi
            fi
        fi
    fi

    # --- third link: a quote crosses a threshold and the alert is delivered ------

    section 'Live: a quote crosses a threshold and the alert is delivered'

    WATCH_URL="http://${SERVICE_HOST}:${WATCHLISTS_PORT}"

    if ! service_reachable watchlists; then
        skip "the alert probe: the watchlists service did not answer."
    elif [ -z "${ACCESS_TOKEN}" ]; then
        skip "the alert probe: it needs the token the sign-in did not produce."
    elif [ -z "${MARKET_DATA_PUBLISH_CMD}" ]; then
        skip "the alert probe: MARKET_DATA_PUBLISH_CMD in manifest.env is empty."
        note "declare one command putting a single market-data quote onto the"
        note "topic, at a price that crosses an alert this account holds, and the"
        note "harness watches the alert change state. Until then the alert path is"
        note "demonstrated at the review, with your poller running and the price"
        note "moving through the level."
    elif [ -z "${WATCHLIST_ALERTS_PATH}" ] || [ -z "${WATCHLIST_TRIGGERED_MARKER}" ]; then
        skip "the alert probe: WATCHLIST_ALERTS_PATH or WATCHLIST_TRIGGERED_MARKER is empty."
        note "the probe reads alert state after the quote, so it needs the route"
        note "and the word that says an alert has fired."
    else
        SETUP_OK=1
        if [ -n "${WATCHLIST_ALERT_SETUP_PATH}" ]; then
            request "${WATCHLIST_ALERT_SETUP_METHOD:-POST}" \
                "${WATCH_URL}${WATCHLIST_ALERT_SETUP_PATH}" \
                "${ACCESS_TOKEN}" "${WATCHLIST_ALERT_SETUP_BODY}"
            case "${HTTP_STATUS}" in
                2*)
                    pass "created an alert through ${WATCHLIST_ALERT_SETUP_METHOD:-POST} ${WATCHLIST_ALERT_SETUP_PATH}, HTTP ${HTTP_STATUS}"
                    note "this run leaves that alert behind. Everything else the"
                    note "harness does only reads."
                    ;;
                *)
                    SETUP_OK=0
                    fail "${WATCHLIST_ALERT_SETUP_METHOD:-POST} ${WATCHLIST_ALERT_SETUP_PATH} answered HTTP ${HTTP_STATUS}." \
                        "Body: ${HTTP_BODY:-empty}" \
                        "The body sent was: ${WATCHLIST_ALERT_SETUP_BODY:-empty}" \
                        "Correct the three WATCHLIST_ALERT_SETUP keys in" \
                        "manifest.env to match the API your team designed, or" \
                        "empty WATCHLIST_ALERT_SETUP_PATH and seed the alert" \
                        "yourself before running this."
                    ;;
            esac
        else
            skip "creating an alert: WATCHLIST_ALERT_SETUP_PATH is empty."
            note "the probe below then depends on an alert already existing for"
            note "account ${DEMO_ACCOUNT_ID} at a level the quote crosses."
        fi

        if [ "${SETUP_OK}" -eq 1 ]; then
            # Counted immediately before the quote goes out, not at the start of
            # the run, so that the record the trade event produced is not read as
            # the record the alert produced.
            ALERT_NOTIF_BEFORE=""
            ALERT_NOTIF_BEFORE="$(notification_count)" || ALERT_NOTIF_BEFORE=""

            if run_declared "MARKET_DATA_PUBLISH_CMD" "${MARKET_DATA_PUBLISH_CMD}"; then
                note "waiting ${ALERT_SETTLE_SECONDS:-20}s for the evaluation, the call to notifications and the delivery"
                sleep "${ALERT_SETTLE_SECONDS:-20}"

                request GET "${WATCH_URL}${WATCHLIST_ALERTS_PATH}" "${ACCESS_TOKEN}" ""
                if [ "${HTTP_STATUS}" != "200" ]; then
                    fail "GET ${WATCHLIST_ALERTS_PATH} answered HTTP ${HTTP_STATUS}." \
                        "Body: ${HTTP_BODY:-empty}" \
                        "Alert state has to be readable by the customer who set" \
                        "the alert, and the probe reads it here."
                elif printf '%s' "${HTTP_BODY}" | grep -q -- "${WATCHLIST_TRIGGERED_MARKER}"; then
                    pass "an alert reads as ${WATCHLIST_TRIGGERED_MARKER} after the quote crossed the threshold"
                else
                    fail "No alert reads as ${WATCHLIST_TRIGGERED_MARKER} after the quote." \
                        "Body: ${HTTP_BODY:-empty}" \
                        "The quote was published and no alert changed state." \
                        "Check that the symbol and the price in" \
                        "MARKET_DATA_PUBLISH_CMD cross the threshold in the alert," \
                        "in the direction the alert was set, and that the consumer" \
                        "is reading the topic. If your alert state uses another" \
                        "word for fired, correct WATCHLIST_TRIGGERED_MARKER in" \
                        "manifest.env."
                fi

                if [ -n "${ALERT_NOTIF_BEFORE}" ]; then
                    ALERT_NOTIF_AFTER=""
                    if ALERT_NOTIF_AFTER="$(notification_count)" \
                        && [ "${ALERT_NOTIF_AFTER}" -gt "${ALERT_NOTIF_BEFORE}" ]; then
                        pass "the notification history grew from ${ALERT_NOTIF_BEFORE} to ${ALERT_NOTIF_AFTER} records after the quote"
                        note "a record appeared between the quote going out and now,"
                        note "which is the closest this gets to the criterion."
                        note "Whether that record is the alert, and whether it left"
                        note "the platform on the channel the customer chose, are"
                        note "shown to your instructor."
                    else
                        fail "The notification history holds ${ALERT_NOTIF_AFTER:-no readable} record(s), against ${ALERT_NOTIF_BEFORE} before the quote." \
                            "The criterion is that a triggered alert is delivered" \
                            "through the notifications service, not written to a" \
                            "log. An alert that fires and leaves no notification" \
                            "record behind has not met it." \
                            "If the alert above did not fire either, fix that" \
                            "first: nothing is delivered for an alert that never" \
                            "triggered."
                    fi
                else
                    skip "checking the notification behind the alert: the notification history could not be read."
                    note "delivery through notifications is the criterion here, and"
                    note "the probe counts records either side of the quote. It needs"
                    note "the notifications service up and NOTIFICATIONS_HISTORY_PATH"
                    note "set."
                fi
            fi
        fi
    fi

    # --- the contract, for the portfolio service only ---------------------------

    section 'Live: the portfolio contract'

    PORTFOLIO_URL="http://${SERVICE_HOST}:${PORTFOLIO_PORT}"

    if ! service_reachable portfolio; then
        skip "the contract-shape probes: the portfolio service did not answer."
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
        request GET "${PORTFOLIO_URL}${SUMMARY_PATH}" "${ACCESS_TOKEN}" ""
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
        request GET "${PORTFOLIO_URL}${POSITIONS_PATH}" "${ACCESS_TOKEN}" ""
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

    section 'Live: what was not probed'

    skip "the channel a notification went out on: no route on the platform reports it."
    skip "idempotency on a replayed event: the harness publishes once and will not replay into your stack."
    skip "the default account applied at the next sign-in: it spans two sessions and a screen."
    skip "a second customer's data reached with the first customer's token: it needs two seeded accounts."
    note "all four are acceptance criteria and all four are demonstrated to your"
    note "instructor. A harness that cannot see something says so rather than"
    note "passing quietly."
fi

# --- result ------------------------------------------------------------------------

printf '\n%s\n' '----------------------------------------------------------------'
printf '%s passed, %s failed\n' "${PASSED}" "${FAILED}"

if [ "${FAILED}" -eq 0 ]; then
    if [ "${LIVE}" -eq 0 ]; then
        printf '\nThe harness is satisfied by the static checks. It has read your\n'
        printf 'manifest, counted your decision log entries and read your combined\n'
        printf 'review, and it has not sent a single request. Run it again with\n'
        printf '%s\n' '--live once the four services are up.'
    else
        printf '\nThe harness is satisfied. Four services answered, refused two\n'
        printf 'tokens each and admitted one, and the chain moved as far as it can\n'
        printf 'be watched from outside.\n'
    fi
    printf '\nThe rest of this sprint is assessed by a person. Whether the four\n'
    printf 'services are integrated or merely running, whether a notification went\n'
    printf 'to the channel the customer chose, whether the log records decisions or\n'
    printf 'events, whether the review is a reading of your services, and whether\n'
    printf 'the demonstration ran on live data are all read at the review.\n'
    exit 0
fi

printf '\nEach failure above says what was expected and where to look. Nothing\n'
printf 'here reads your backlog or your scope agreement, and both are assessed.\n'

exit 1
