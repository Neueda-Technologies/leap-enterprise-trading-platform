#!/usr/bin/env bash
#
# Sprint 11 acceptance harness.
#
#   check.sh              static checks only. No network, nothing deployed.
#   check.sh --live       the static checks, then the probes against your
#                         deployed distribution and your bucket.
#
# Static mode reads manifest.env, checks the shape of the bucket name and
# distribution domain you declared, reads your deployment entry point and
# confirms it covers the build, upload and invalidate stages, and searches the
# repository for anything shaped like an AWS access key.
#
# Live mode needs the deployment to exist and needs network access. It fetches
# your distribution over HTTPS and confirms the answer is your application, it
# addresses your bucket's own endpoints and confirms they refuse, and it fetches
# the JavaScript your distribution serves and runs the Sprint 9 secret patterns
# over it. It holds no AWS credentials and asks for none: everything it checks,
# it checks from outside, the way a customer would.
#
# This harness is lighter than every harness before it, and it depends on the
# network. Most of this sprint happens in an account it cannot see and in a room
# it is not in: the origin access control, the IAM policy, the approval on a
# deploy and the showcase are all read by a person. A live failure is worth a
# second run before it is worth an hour of debugging, because a distribution
# that has just been created answers oddly until it reaches Deployed.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPRINT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
MANIFEST="${SPRINT_DIR}/manifest.env"

LIVE=0
while [ "$#" -gt 0 ]; do
    case "$1" in
        --live) LIVE=1; shift ;;
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

printf 'Sprint 11 acceptance harness\n'
if [ "${LIVE}" -eq 1 ]; then
    printf 'Static checks, then live probes against your deployment.\n'
else
    printf 'Static checks only. Add --live once the distribution is up.\n'
fi

# --- the manifest ------------------------------------------------------------------

section 'Manifest'

[ -f "${MANIFEST}" ] || abort \
    "No manifest.env in ${SPRINT_DIR}." \
    "The harness reads your distribution domain, your bucket name and the path" \
    "to your deployment entry point from that file. If you have deleted it," \
    "restore it from the repository."

CLOUDFRONT_DOMAIN=""
BUCKET_NAME=""
AWS_REGION=""
DEPLOY_ENTRYPOINT=""
DEPLOY_SUPPORTING_FILES=""
DEPLOY_BUILD_PATTERN=""
DEPLOY_UPLOAD_PATTERN=""
DEPLOY_INVALIDATE_PATTERN=""
REPO_SCAN_ROOT=""
AWS_ACCESS_KEY_ID_PATTERN=""
AWS_SECRET_KEY_PATTERN=""
SCAN_EXCLUDE_DIRS=""
INDEX_APP_MARKER_PATTERN=""
BUNDLE_FETCH_LIMIT=""
BUNDLE_API_KEY_PATTERN=""
BUNDLE_FAUXNANCE_URL_PATTERN=""
BUNDLE_SECRET_PATTERN=""

# shellcheck source=/dev/null
. "${MANIFEST}"

STATIC_KEYS="DEPLOY_ENTRYPOINT DEPLOY_BUILD_PATTERN DEPLOY_UPLOAD_PATTERN
DEPLOY_INVALIDATE_PATTERN REPO_SCAN_ROOT AWS_ACCESS_KEY_ID_PATTERN
AWS_SECRET_KEY_PATTERN SCAN_EXCLUDE_DIRS"

LIVE_KEYS="CLOUDFRONT_DOMAIN BUCKET_NAME AWS_REGION INDEX_APP_MARKER_PATTERN
BUNDLE_FETCH_LIMIT BUNDLE_API_KEY_PATTERN BUNDLE_FAUXNANCE_URL_PATTERN
BUNDLE_SECRET_PATTERN"

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
        "DEPLOY_ENTRYPOINT is the path to the one script that does" \
        "your deploy. CLOUDFRONT_DOMAIN, BUCKET_NAME and AWS_REGION describe" \
        "what you deployed to, and live mode cannot probe anything without" \
        "them. Every other key ships with a defensible default: set the ones" \
        "your team decided differently and leave the rest alone." \
        "DEPLOY_SUPPORTING_FILES is optional, and an empty value there means" \
        "the three stages are searched for in the entry point alone."
fi

if [ -n "${BUNDLE_FETCH_LIMIT}" ]; then
    printf '%s' "${BUNDLE_FETCH_LIMIT}" | grep -qE '^[0-9]+$' || abort \
        "BUNDLE_FETCH_LIMIT in manifest.env is not a whole number: ${BUNDLE_FETCH_LIMIT}"
fi

pass "manifest.env declares every name the harness needs"

# The two names the whole sprint is addressed by. They are checked here rather
# than at the point of use, so that a typo is a manifest problem on the Monday
# and not a mysterious denial on the Friday.
TARGET_DECLARED=1
for key in CLOUDFRONT_DOMAIN BUCKET_NAME; do
    eval "value=\${${key}}"
    if [ -z "${value}" ] || [ "${value}" = "CHANGE_ME" ]; then
        TARGET_DECLARED=0
    fi
done

if [ "${TARGET_DECLARED}" -eq 0 ]; then
    skip "the deployment target: CLOUDFRONT_DOMAIN and BUCKET_NAME are not both set."
    note "on the Monday that is the correct answer, because neither exists yet."
    note "Declare them once the bucket and the distribution are up. Live mode"
    note "cannot run at all until they are."
else
    TARGET_PROBLEMS=""
    case "${CLOUDFRONT_DOMAIN}" in
        *://*) TARGET_PROBLEMS="${TARGET_PROBLEMS} CLOUDFRONT_DOMAIN carries a scheme; give the hostname only." ;;
        */*)   TARGET_PROBLEMS="${TARGET_PROBLEMS} CLOUDFRONT_DOMAIN carries a path or a trailing slash; give the hostname only." ;;
        *.*)   ;;
        *)     TARGET_PROBLEMS="${TARGET_PROBLEMS} CLOUDFRONT_DOMAIN is not a hostname." ;;
    esac

    if ! printf '%s' "${BUCKET_NAME}" | grep -qE '^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$'; then
        TARGET_PROBLEMS="${TARGET_PROBLEMS} BUCKET_NAME is not a legal S3 bucket name: three to sixty-three characters, lowercase letters, digits, dots and hyphens only."
    fi

    if [ -z "${TARGET_PROBLEMS}" ]; then
        pass "manifest declares the distribution domain ${CLOUDFRONT_DOMAIN} and the bucket ${BUCKET_NAME} in ${AWS_REGION:-an undeclared region}"
    else
        fail "The declared deployment target does not have the right shape." \
            "${TARGET_PROBLEMS# }" \
            "The harness builds https://${CLOUDFRONT_DOMAIN}/ and the bucket's" \
            "own endpoints from these two values, so a value with a scheme or a" \
            "path in it probes something that is not your deployment."
    fi
fi

# --- the deployment entry point -----------------------------------------------------

section 'The deployment entry point'

ENTRYPOINT_PATH="${SPRINT_DIR}/${DEPLOY_ENTRYPOINT}"
DEPLOY_FILES=""

if [ ! -f "${ENTRYPOINT_PATH}" ]; then
    fail "No file at ${DEPLOY_ENTRYPOINT}, relative to ${SPRINT_DIR}." \
        "Criterion 4 is one script covering build, upload and invalidation." \
        "Write it, commit it, and name its path in DEPLOY_ENTRYPOINT in" \
        "manifest.env. A script at the repository root would be" \
        "../deploy/deploy-ui.sh." \
        "A deploy that is a sequence of commands in somebody's shell history" \
        "does not satisfy this, and it is the thing that fails on the Friday."
else
    DEPLOY_FILES="${ENTRYPOINT_PATH}"
    SUPPORTING_MISSING=""
    for extra in ${DEPLOY_SUPPORTING_FILES}; do
        if [ -f "${SPRINT_DIR}/${extra}" ]; then
            DEPLOY_FILES="${DEPLOY_FILES} ${SPRINT_DIR}/${extra}"
        else
            SUPPORTING_MISSING="${SUPPORTING_MISSING} ${extra}"
        fi
    done

    if [ -n "${SUPPORTING_MISSING}" ]; then
        fail "DEPLOY_SUPPORTING_FILES names file(s) that are not there:${SUPPORTING_MISSING}" \
            "Correct the paths, or empty the key and the stages are searched for" \
            "in the entry point alone."
    else
        pass "the deployment entry point is ${DEPLOY_ENTRYPOINT}"
    fi

    if [ ! -x "${ENTRYPOINT_PATH}" ]; then
        note "${DEPLOY_ENTRYPOINT} is not executable. Not a criterion, and still"
        note "worth fixing: chmod +x it, so that one command is one command"
        note "rather than one command with bash in front of it."
    fi

    stage_check() {
        stage_label="$1"
        stage_pattern="$2"
        stage_advice="$3"

        # shellcheck disable=SC2086
        if grep -qEi "${stage_pattern}" ${DEPLOY_FILES} 2>/dev/null; then
            pass "the ${stage_label} stage is present in the deployment"
        else
            fail "No ${stage_label} stage in the deployment." \
                "Searched: ${DEPLOY_ENTRYPOINT}${DEPLOY_SUPPORTING_FILES:+ and ${DEPLOY_SUPPORTING_FILES}}" \
                "Pattern: ${stage_pattern}" \
                "${stage_advice}" \
                "If your deployment does this stage some other way, widen the" \
                "pattern in manifest.env and be ready to explain it at the" \
                "review. A script that calls a second script keeps its stages" \
                "in two files: name the second in DEPLOY_SUPPORTING_FILES and" \
                "both are searched."
        fi
    }

    stage_check "build" "${DEPLOY_BUILD_PATTERN}" \
        "The deploy starts from a clean install and a production build, not from whatever is in dist/."
    stage_check "upload" "${DEPLOY_UPLOAD_PATTERN}" \
        "The build output has to reach the bucket, and the bucket has to end up holding this build rather than a mixture of this one and the last."
    stage_check "invalidation" "${DEPLOY_INVALIDATE_PATTERN}" \
        "Without it, the edge keeps serving the previous build and you debug code that is not running."

    note "this reads the file. It does not run it, deploys nothing, and cannot"
    note "tell whether it works, whether a second run is safe, or whether one"
    note "person can run it unaided. All three are read at the review."
fi

# --- keys in the repository ----------------------------------------------------------

section 'AWS credentials in the repository'

SCAN_ROOT="$(cd "${SPRINT_DIR}/${REPO_SCAN_ROOT}" 2>/dev/null && pwd || true)"

if [ -z "${SCAN_ROOT}" ] || [ ! -d "${SCAN_ROOT}" ]; then
    fail "REPO_SCAN_ROOT names ${REPO_SCAN_ROOT}, and there is no directory there." \
        "It is the tree the key scan searches, relative to this folder, and the" \
        "repository root is the right answer for it."
else
    EXCLUDE_ARGS=""
    for dir in ${SCAN_EXCLUDE_DIRS}; do
        EXCLUDE_ARGS="${EXCLUDE_ARGS} --exclude-dir=${dir}"
    done

    scan_tree() {
        scan_label="$1"
        scan_pattern="$2"
        scan_case="$3"
        scan_advice="$4"

        if [ "${scan_case}" = "insensitive" ]; then
            # shellcheck disable=SC2086
            scan_hits="$(grep -rIlEi ${EXCLUDE_ARGS} -- "${scan_pattern}" "${SCAN_ROOT}" 2>/dev/null | LC_ALL=C sort | head -n 10 || true)"
        else
            # shellcheck disable=SC2086
            scan_hits="$(grep -rIlE ${EXCLUDE_ARGS} -- "${scan_pattern}" "${SCAN_ROOT}" 2>/dev/null | LC_ALL=C sort | head -n 10 || true)"
        fi

        if [ -z "${scan_hits}" ]; then
            pass "no ${scan_label} anywhere in the working tree"
        else
            fail "The working tree matches the ${scan_label} pattern." \
                "Pattern: ${scan_pattern}" \
                "${scan_advice}" \
                "In:"
            printf '%s\n' "${scan_hits}" | sed 's/^/        /'
            printf '        %s\n' \
                "The harness names the file and never prints what it matched." \
                "Treat the credential as disclosed: deactivate and delete the" \
                "key in IAM first, then take it out of the tree. Deleting it" \
                "from the file is not the fix and is not the order."
        fi
    }

    scan_tree "access key id" "${AWS_ACCESS_KEY_ID_PATTERN}" sensitive \
        "An access key id is half a credential and it names the account it belongs to."

    scan_tree "secret access key" "${AWS_SECRET_KEY_PATTERN}" insensitive \
        "That is the other half. A pair in a repository is an account somebody else can deploy to."

    note "this reads the files as they are now. A key that was committed and"
    note "then removed is still a disclosed key, it is still in the history,"
    note "and it still fails criterion 6 at the review. Rotation is the fix."
    note "Directories skipped: ${SCAN_EXCLUDE_DIRS}."
fi

# --- history for this sprint's files ---------------------------------------------------

section 'History of this sprint'

if ! command -v git >/dev/null 2>&1; then
    skip "the history scan: git is not on your PATH."
    note "with git present the harness also searches the recorded history of"
    note "this folder, because a key deleted in a later commit is still in the"
    note "one before it."
elif ! git -C "${SPRINT_DIR}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    skip "the history scan: ${SPRINT_DIR} is not inside a git working tree."
    note "the check runs once this sprint's work is committed in the repository."
else
    HISTORY_HITS="$(git -C "${SPRINT_DIR}" log --all -p -- . 2>/dev/null \
        | grep -cE "${AWS_ACCESS_KEY_ID_PATTERN}" || true)"
    HISTORY_HITS="${HISTORY_HITS//[^0-9]/}"

    if [ -z "${HISTORY_HITS}" ] || [ "${HISTORY_HITS}" -eq 0 ]; then
        pass "no access key id in the recorded history of this sprint's folder"
        note "this searches this folder only, because that is the part of the"
        note "history this sprint added. A key committed elsewhere in the"
        note "repository, at any point, in any branch, is the same finding."
    else
        fail "An access key id appears ${HISTORY_HITS} time(s) in the history of this folder." \
            "It is in a commit, whether or not it is in the file today." \
            "Deactivate and delete that key in IAM now. Then talk to your" \
            "instructor about the history: rewriting it is a decision for the" \
            "whole team, and rotating the credential is not optional either" \
            "way." \
            "Find the commits with:" \
            "  git log --all -p -- ${SPRINT_DIR##*/} | grep -nE '${AWS_ACCESS_KEY_ID_PATTERN}'"
    fi
fi

# --- live mode ------------------------------------------------------------------------

if [ "${LIVE}" -eq 1 ]; then

    command -v curl >/dev/null 2>&1 || abort \
        "curl is not on your PATH, and live mode reaches your deployment with it."

    BODY_FILE="$(mktemp)"
    INDEX_FILE="$(mktemp)"
    BUNDLE_DIR="$(mktemp -d)"
    trap 'rm -rf "${BODY_FILE}" "${INDEX_FILE}" "${BUNDLE_DIR}"' EXIT

    HTTP_STATUS=""
    FINAL_URL=""

    # One fetch helper for every probe below. It truncates the body file first,
    # so that a request that never connected cannot be read as the answer to a
    # previous one.
    fetch() {
        fetch_url="$1"
        shift
        : >"${BODY_FILE}"
        if fetch_result="$(curl -s -o "${BODY_FILE}" \
            -w '%{http_code} %{url_effective}' \
            --max-time 25 "$@" "${fetch_url}" 2>/dev/null)"; then
            HTTP_STATUS="${fetch_result%% *}"
            FINAL_URL="${fetch_result#* }"
        else
            HTTP_STATUS="000"
            FINAL_URL="${fetch_url}"
        fi
    }

    # S3 reports its refusals in two shapes: an XML <Code> from the REST
    # endpoint, and an HTML list item from the website endpoint. Read both.
    error_code() {
        ec="$(tr -d '\n' <"${BODY_FILE}" \
            | sed -n 's/.*<Code>\([A-Za-z]*\)<\/Code>.*/\1/p' | head -n 1 || true)"
        if [ -z "${ec}" ]; then
            ec="$(sed -n 's/.*Code:[[:space:]]*\([A-Za-z]*\).*/\1/p' "${BODY_FILE}" \
                | head -n 1 || true)"
        fi
        printf '%s' "${ec}"
    }

    SITE_URL="https://${CLOUDFRONT_DOMAIN}/"

    # --- the deployed application ------------------------------------------------

    section 'The application over HTTPS'

    fetch "${SITE_URL}" -L --max-redirs 5
    INDEX_STATUS="${HTTP_STATUS}"
    cp "${BODY_FILE}" "${INDEX_FILE}"

    case "${INDEX_STATUS}" in
        000)
            fail "${SITE_URL} did not answer." \
                "Criterion 1 is the application reachable over HTTPS through the" \
                "distribution. Check the distribution's status is Deployed" \
                "rather than In Progress, which takes several minutes after a" \
                "change, and check CLOUDFRONT_DOMAIN in manifest.env is the" \
                "domain the distribution reports."
            ;;
        200)
            case "${FINAL_URL}" in
                https://*)
                    if grep -qEi "${INDEX_APP_MARKER_PATTERN}" "${INDEX_FILE}"; then
                        pass "${SITE_URL} serves your application over HTTPS"
                        note "the marker searched for is ${INDEX_APP_MARKER_PATTERN}."
                        note "That the page is your build is all this can see."
                        note "Whether the authenticated flows work from it is"
                        note "criterion 5, and it is demonstrated, not scripted"
                        note "here."
                    else
                        fail "${SITE_URL} answered 200, and the body is not your application." \
                            "Searched for: ${INDEX_APP_MARKER_PATTERN}" \
                            "A bucket holding the wrong files, a default root" \
                            "object that is not index.html, and an error" \
                            "document served with a 200 all look like this." \
                            "Open the URL and read what came back."
                    fi
                    ;;
                *)
                    fail "${SITE_URL} answered 200, and the request ended at ${FINAL_URL}." \
                        "Criterion 1 is HTTPS. Something in the chain redirected" \
                        "to plain HTTP, and a login form served over HTTP is the" \
                        "finding, not the redirect."
                    ;;
            esac
            ;;
        403|404)
            fail "${SITE_URL} answered ${INDEX_STATUS}." \
                "Behind an origin access control a missing key comes back as" \
                "403, not 404, because an anonymous caller may not learn whether" \
                "an object exists. So this is one of: nothing uploaded yet, a" \
                "default root object that is not index.html, or a bucket policy" \
                "that does not yet trust this distribution." \
                "Body: $(head -c 200 "${INDEX_FILE}" | tr -d '\n')"
            ;;
        *)
            fail "${SITE_URL} answered ${INDEX_STATUS}." \
                "Criterion 1 is a working application over HTTPS through the" \
                "distribution." \
                "Body: $(head -c 200 "${INDEX_FILE}" | tr -d '\n')"
            ;;
    esac

    fetch "http://${CLOUDFRONT_DOMAIN}/"
    case "${HTTP_STATUS}" in
        000)
            skip "the plain-HTTP probe: http://${CLOUDFRONT_DOMAIN}/ did not answer."
            note "not a failure on its own. The criterion is that HTTPS works,"
            note "and refusing HTTP outright is one acceptable way to reach it."
            ;;
        301|302|307|308)
            pass "plain HTTP is redirected to HTTPS (${HTTP_STATUS})"
            ;;
        2*)
            fail "http://${CLOUDFRONT_DOMAIN}/ answered ${HTTP_STATUS} and served content." \
                "The distribution is serving your application unencrypted. Set" \
                "the viewer protocol policy to redirect HTTP to HTTPS, or to" \
                "HTTPS only."
            ;;
        *)
            pass "plain HTTP is not served (${HTTP_STATUS})"
            ;;
    esac

    # --- the bucket refuses -------------------------------------------------------

    section 'The bucket refuses direct access'

    S3_REST_URL="https://${BUCKET_NAME}.s3.${AWS_REGION}.amazonaws.com/index.html"
    fetch "${S3_REST_URL}"
    REST_STATUS="${HTTP_STATUS}"
    REST_CODE="$(error_code)"

    case "${REST_STATUS}" in
        000)
            skip "the REST endpoint probe: ${S3_REST_URL} did not answer."
            note "criterion 2 is unproven until it does. Check your network"
            note "before assuming the bucket is fine."
            ;;
        2*)
            fail "${S3_REST_URL} answered ${REST_STATUS}." \
                "The bucket is readable by anyone who knows its name, which is" \
                "criterion 2 failed and criterion 3 with it. A site that works" \
                "this way works because the bucket is public, not because the" \
                "distribution is trusted." \
                "Block all public access on the bucket, remove any policy with a" \
                "wildcard principal, and let the origin access control be the" \
                "only thing the bucket trusts."
            ;;
        403)
            pass "${S3_REST_URL} refuses: ${REST_STATUS} ${REST_CODE:-with no error code in the body}"
            ;;
        404)
            case "${REST_CODE}" in
                NoSuchBucket)
                    fail "${S3_REST_URL} answered 404 NoSuchBucket." \
                        "That is not a denial, it is a bucket that does not" \
                        "exist at this address. Either BUCKET_NAME or AWS_REGION" \
                        "in manifest.env is wrong, or the bucket was deleted." \
                        "A criterion cannot be satisfied by a name nobody owns."
                    ;;
                *)
                    fail "${S3_REST_URL} answered 404 ${REST_CODE:-with no error code in the body}." \
                        "A private bucket refuses an anonymous caller with 403" \
                        "before it tells them whether a key exists. A 404 for a" \
                        "missing key means the caller is permitted to list the" \
                        "bucket, which is more access than criterion 2 allows."
                    ;;
            esac
            ;;
        301|307)
            fail "${S3_REST_URL} answered ${REST_STATUS} ${REST_CODE:-}." \
                "The bucket exists in a different region from the one declared" \
                "in AWS_REGION. Correct the manifest and run this again: until" \
                "then this probe is addressing the wrong endpoint and proves" \
                "nothing either way."
            ;;
        *)
            fail "${S3_REST_URL} answered ${REST_STATUS} ${REST_CODE:-with no error code in the body}." \
                "Criterion 2 is a bucket that returns access denied when it is" \
                "addressed directly. Read the body and work out which of the" \
                "bucket, the region and the public access block is not what you" \
                "think it is."
            ;;
    esac

    # The website endpoint is a separate front door with its own hostname, and a
    # bucket can be private on one and public on the other. Both regional forms
    # are probed: the older regions use a hyphen before the region, the newer
    # ones a dot, and only one of the two resolves for any given region.
    WEBSITE_PUBLIC=0
    WEBSITE_REPORT=""
    for host in "${BUCKET_NAME}.s3-website.${AWS_REGION}.amazonaws.com" \
        "${BUCKET_NAME}.s3-website-${AWS_REGION}.amazonaws.com"; do
        fetch "http://${host}/"
        site_status="${HTTP_STATUS}"
        site_code="$(error_code)"
        case "${site_status}" in
            000) WEBSITE_REPORT="${WEBSITE_REPORT}
        ${host}  no answer, so no website endpoint there" ;;
            2*)
                WEBSITE_PUBLIC=1
                WEBSITE_REPORT="${WEBSITE_REPORT}
        ${host}  ${site_status}, serving content" ;;
            *) WEBSITE_REPORT="${WEBSITE_REPORT}
        ${host}  ${site_status} ${site_code:-no error code in the body}" ;;
        esac
    done

    if [ "${WEBSITE_PUBLIC}" -eq 0 ]; then
        pass "neither S3 website endpoint serves the site"
        printf '%s\n' "${WEBSITE_REPORT#$'\n'}"
    else
        fail "An S3 website endpoint is serving your site." \
            "Static website hosting on the bucket is a second, public front" \
            "door that bypasses the distribution entirely: no HTTPS, no cache" \
            "policy, no origin access control. Criterion 3 asks for the" \
            "distribution to be the only way in." \
            "Disable static website hosting on the bucket. The distribution" \
            "reads the bucket's REST endpoint, not its website endpoint, so" \
            "nothing you need depends on it."
        printf '%s\n' "${WEBSITE_REPORT#$'\n'}"
    fi

    note "what this cannot see is how the bucket is refusing. A bucket that is"
    note "private because nobody has made it public refuses exactly like a"
    note "bucket that is private with an origin access control in front of it."
    note "Criterion 3 is read from your configuration at the review."

    # --- the deployed bundle ------------------------------------------------------

    section 'Bundle hygiene, against what is deployed'

    if [ "${INDEX_STATUS}" != "200" ]; then
        skip "the bundle scan: ${SITE_URL} did not serve a page to read the scripts from."
        note "Sprint 9 scanned the bundle in dist/ on your machine. This scans"
        note "the copy your distribution serves, which is the one the world has."
    else
        BUNDLE_COUNT=0
        BUNDLE_REFERENCED=0
        BUNDLE_MISSED=""

        while IFS= read -r src; do
            [ -n "${src}" ] || continue
            BUNDLE_REFERENCED=$((BUNDLE_REFERENCED + 1))
            [ "${BUNDLE_COUNT}" -ge "${BUNDLE_FETCH_LIMIT}" ] && break

            case "${src}" in
                http://*|https://*) bundle_url="${src}" ;;
                /*)                 bundle_url="https://${CLOUDFRONT_DOMAIN}${src}" ;;
                ./*)                bundle_url="https://${CLOUDFRONT_DOMAIN}/${src#./}" ;;
                *)                  bundle_url="https://${CLOUDFRONT_DOMAIN}/${src}" ;;
            esac

            fetch "${bundle_url}"
            if [ "${HTTP_STATUS}" = "200" ]; then
                BUNDLE_COUNT=$((BUNDLE_COUNT + 1))
                cp "${BODY_FILE}" "${BUNDLE_DIR}/${BUNDLE_COUNT}.js"
                printf '%s\n' "${bundle_url}" >"${BUNDLE_DIR}/${BUNDLE_COUNT}.url"
            else
                BUNDLE_MISSED="${BUNDLE_MISSED}
        ${bundle_url}  ${HTTP_STATUS}"
            fi
        done < <(grep -oE 'src="[^"]+\.js[^"]*"' "${INDEX_FILE}" \
            | sed 's/^src="//; s/"$//' | LC_ALL=C sort -u || true)

        if [ "${BUNDLE_REFERENCED}" -eq 0 ]; then
            fail "The deployed page references no JavaScript at all." \
                "The harness reads script tags out of the deployed index. An" \
                "Angular build has at least one. A page with none is not your" \
                "application, whatever it is, so read what the distribution" \
                "returned before looking anywhere else."
        elif [ "${BUNDLE_COUNT}" -eq 0 ]; then
            fail "None of the ${BUNDLE_REFERENCED} script(s) on the deployed page could be fetched." \
                "The harness reads script tags out of the deployed index and" \
                "fetches each one. None of them answered 200, which means the" \
                "page references assets that are not in the bucket. That is a" \
                "half-finished upload, and the site is broken for every visitor" \
                "whether or not the page itself renders."
            [ -n "${BUNDLE_MISSED}" ] && printf '%s\n' "${BUNDLE_MISSED#$'\n'}"
        else
            scan_deployed() {
                scan_label="$1"
                scan_pattern="$2"
                scan_advice="$3"

                scan_hits="$(grep -rlEi -- "${scan_pattern}" "${BUNDLE_DIR}" 2>/dev/null \
                    | LC_ALL=C sort || true)"

                if [ -z "${scan_hits}" ]; then
                    pass "no ${scan_label} in the deployed JavaScript"
                else
                    fail "The deployed JavaScript matches the ${scan_label} pattern." \
                        "Pattern: ${scan_pattern}" \
                        "${scan_advice}" \
                        "In:"
                    while IFS= read -r hit; do
                        [ -n "${hit}" ] || continue
                        hit_url="$(cat "${hit%.js}.url" 2>/dev/null || printf '%s' "${hit}")"
                        printf '        %s\n' "${hit_url}"
                    done <<<"${scan_hits}"
                fi
            }

            pass "${BUNDLE_COUNT} script(s) fetched from the deployed page"
            if [ -n "${BUNDLE_MISSED}" ]; then
                printf '        %s\n' "Referenced and not fetched:"
                printf '%s\n' "${BUNDLE_MISSED#$'\n'}"
            fi

            scan_deployed "market-data key" "${BUNDLE_API_KEY_PATTERN}" \
                "This bundle is a public object on a CDN. A key in it has been published, and it is cached at edges you do not control."

            scan_deployed "market-data address" "${BUNDLE_FAUXNANCE_URL_PATTERN}" \
                "The Angular application never calls the market-data API. Prices reach the browser through your own services, which hold the key server-side."

            scan_deployed "signing secret" "${BUNDLE_SECRET_PATTERN}" \
                "A signing secret in the bundle lets any reader mint a token every service in the platform accepts. Nothing signs anything in a browser."

            note "this reads the deployed files as text, up to"
            note "BUNDLE_FETCH_LIMIT=${BUNDLE_FETCH_LIMIT} of them. A lazily"
            note "loaded chunk that was not referenced by the index is not"
            note "fetched, and a value assembled at runtime from fragments"
            note "passes here and is still a leak. Both are asked about."
        fi
    fi
fi

# --- result -----------------------------------------------------------------------

printf '\n%s\n' '----------------------------------------------------------------'
printf '%s passed, %s failed\n' "${PASSED}" "${FAILED}"

if [ "${FAILED}" -eq 0 ]; then
    if [ "${LIVE}" -eq 0 ]; then
        printf '\nThe harness is satisfied by the static checks. It has read your\n'
        printf 'manifest, read your deployment entry point and searched your tree\n'
        printf 'for credentials, and it has not sent a single request. Nothing here\n'
        printf 'has been near AWS. Run it again with --live once the distribution\n'
        printf 'is up.\n'
    else
        printf '\nThe harness is satisfied. It has loaded your application over\n'
        printf 'HTTPS, been refused by your bucket, and read the JavaScript your\n'
        printf 'distribution serves.\n'
    fi
    printf '\nThis harness is lighter than the ones before it, and deliberately so.\n'
    printf 'It holds no AWS credentials, so it cannot see your origin access\n'
    printf 'control, your IAM policy, or who approved the deploy. It cannot run\n'
    printf 'your deployment, so it cannot tell you that a second run is safe. It\n'
    printf 'cannot sign in, so criterion 5 is demonstrated rather than checked.\n'
    printf 'And it is not in the room for the showcase.\n'
    exit 0
fi

printf '\nEach failure above says what was expected and where to look. Live\n'
printf 'checks depend on the network and on a distribution that has finished\n'
printf 'deploying: run it twice before you debug it once.\n'

exit 1
