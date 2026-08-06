#!/usr/bin/env bash
#
# deploy-ui.sh
#
# Builds the Angular UI and deploys it to a private S3 bucket behind CloudFront.
# Reference implementation for Sprint 11 (see deploy/README.md for what this
# means: this script is the marking reference, not a handout).
#
# What it does, in order:
#   1. npm ci and ng build inside ui/
#   2. aws s3 sync the build output to the target bucket, with a long
#      cache-control on the hashed, content-addressed assets and a
#      no-cache header on index.html
#   3. aws cloudfront create-invalidation for /index.html, and wait for it
#      to finish
#
# The script refuses to run with missing configuration, prints every command
# it is about to run before running it, and supports --dry-run so a student
# can see the plan without touching AWS.
#
# Usage:
#   deploy/deploy-ui.sh --bucket my-bucket --distribution-id E1234567890 [options]
#
# Required (flag or environment variable):
#   --bucket             BUCKET               DEPLOY_BUCKET
#   --distribution-id    DISTRIBUTION_ID      DEPLOY_DISTRIBUTION_ID
#
# Optional (flag or environment variable):
#   --profile            PROFILE              AWS_PROFILE
#   --region             REGION               AWS_REGION
#   --ui-dir             DIR (default: ui)    UI_DIR
#   --skip-build                              SKIP_BUILD=1
#   --dry-run                                 DRY_RUN=1
#   -h, --help
#
# Exit codes: 1 configuration error, 2 missing dependency, 3 build failure,
# 4 deploy failure.

set -euo pipefail

# ---------------------------------------------------------------------------
# Defaults, overridable by environment variable, then by flag.
# ---------------------------------------------------------------------------
BUCKET="${DEPLOY_BUCKET:-}"
DISTRIBUTION_ID="${DEPLOY_DISTRIBUTION_ID:-}"
PROFILE="${AWS_PROFILE:-}"
REGION="${AWS_REGION:-}"
UI_DIR="${UI_DIR:-ui}"
SKIP_BUILD="${SKIP_BUILD:-0}"
DRY_RUN="${DRY_RUN:-0}"

SCRIPT_NAME="$(basename "$0")"

log() {
  printf '[%s] %s\n' "$SCRIPT_NAME" "$*"
}

err() {
  printf '[%s] error: %s\n' "$SCRIPT_NAME" "$*" >&2
}

usage() {
  sed -n '2,33p' "$0" | sed 's/^# \{0,1\}//'
}

# ---------------------------------------------------------------------------
# Argument parsing.
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --bucket)
      BUCKET="$2"
      shift 2
      ;;
    --distribution-id)
      DISTRIBUTION_ID="$2"
      shift 2
      ;;
    --profile)
      PROFILE="$2"
      shift 2
      ;;
    --region)
      REGION="$2"
      shift 2
      ;;
    --ui-dir)
      UI_DIR="$2"
      shift 2
      ;;
    --skip-build)
      SKIP_BUILD=1
      shift
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      err "unrecognised argument: $1"
      usage
      exit 1
      ;;
  esac
done

# ---------------------------------------------------------------------------
# Required configuration. Refuse to run rather than guess.
# ---------------------------------------------------------------------------
MISSING=0
if [[ -z "$BUCKET" ]]; then
  err "no bucket set. Pass --bucket or set DEPLOY_BUCKET."
  MISSING=1
fi
if [[ -z "$DISTRIBUTION_ID" ]]; then
  err "no CloudFront distribution id set. Pass --distribution-id or set DEPLOY_DISTRIBUTION_ID."
  MISSING=1
fi
if [[ "$MISSING" -eq 1 ]]; then
  usage
  exit 1
fi

# ---------------------------------------------------------------------------
# Dependency checks.
# ---------------------------------------------------------------------------
for bin in aws npm; do
  if ! command -v "$bin" >/dev/null 2>&1; then
    err "required command not found on PATH: $bin"
    exit 2
  fi
done

if [[ ! -d "$UI_DIR" ]]; then
  err "UI directory not found: $UI_DIR"
  exit 1
fi

# ---------------------------------------------------------------------------
# Build AWS CLI common arguments once, used for every aws invocation below.
# ---------------------------------------------------------------------------
AWS_ARGS=()
if [[ -n "$PROFILE" ]]; then
  AWS_ARGS+=(--profile "$PROFILE")
fi
if [[ -n "$REGION" ]]; then
  AWS_ARGS+=(--region "$REGION")
fi

log "bucket:          $BUCKET"
log "distribution id: $DISTRIBUTION_ID"
log "ui directory:    $UI_DIR"
log "profile:         ${PROFILE:-<default>}"
log "region:          ${REGION:-<default>}"
log "dry run:         $DRY_RUN"
log "skip build:      $SKIP_BUILD"

if [[ "$DRY_RUN" -eq 1 ]]; then
  log "dry run: the build still runs (it only touches the local dist/ folder)."
  log "dry run: aws s3 sync and cp run with --dryrun, and no CloudFront invalidation is created."
fi

# ---------------------------------------------------------------------------
# Build. npm ci for a reproducible install, then ng build. The Angular
# builder picks up the production configuration by default (angular.json
# defaultConfiguration); this script does not second-guess that. This step
# runs even under --dry-run: it only ever writes into the local dist/
# folder, so it carries none of the risk --dry-run exists to avoid, and
# skipping it would leave a dry run with nothing to preview unless a build
# from a previous invocation happened to still be on disk.
# ---------------------------------------------------------------------------
if [[ "$SKIP_BUILD" -eq 1 ]]; then
  log "skipping build (--skip-build set)"
else
  log "installing UI dependencies"
  log "+ (cd $UI_DIR && npm ci)"
  (cd "$UI_DIR" && npm ci)

  log "building the Angular app"
  log "+ (cd $UI_DIR && npx ng build)"
  (cd "$UI_DIR" && npx ng build)
fi

# ---------------------------------------------------------------------------
# Locate the build output. The modern Angular application builder writes to
# dist/<project>/browser. The older browser builder writes straight to
# dist/<project>. Handle both without hard-coding a project name.
# ---------------------------------------------------------------------------
find_dist_dir() {
  local root="$1/dist"
  local candidate=""

  if [[ -d "$root" ]]; then
    candidate="$(find "$root" -maxdepth 2 -type d -name browser -print -quit 2>/dev/null || true)"
  fi

  if [[ -n "$candidate" ]]; then
    printf '%s\n' "$candidate"
    return 0
  fi

  if [[ -d "$root" ]] && find "$root" -maxdepth 1 -name 'index.html' -print -quit | grep -q .; then
    printf '%s\n' "$root"
    return 0
  fi

  # One level down: dist/<project>/index.html
  if [[ -d "$root" ]]; then
    candidate="$(find "$root" -maxdepth 2 -name 'index.html' -print -quit 2>/dev/null || true)"
    if [[ -n "$candidate" ]]; then
      dirname "$candidate"
      return 0
    fi
  fi

  return 1
}

if ! DIST_DIR="$(find_dist_dir "$UI_DIR")"; then
  err "could not find a build output under $UI_DIR/dist. Did the build run? Re-run without --skip-build, or check $UI_DIR/dist by hand."
  exit 3
fi

log "build output:    $DIST_DIR"

if [[ ! -f "$DIST_DIR/index.html" ]]; then
  err "no index.html found in $DIST_DIR. The build did not produce a deployable app."
  exit 3
fi

# ---------------------------------------------------------------------------
# Sync to S3. Two passes so that the two families of files get different
# cache-control headers:
#
#   - Every hashed, content-addressed file (main.<hash>.js, styles.<hash>.css,
#     chunk-<hash>.js, images with a fingerprint in the name) is immutable:
#     once a filename exists, its content never changes, so it can be cached
#     for a year at the browser and at CloudFront.
#   - index.html is not hashed. It is the pointer to the current build, so it
#     must never be served stale. no-cache forces revalidation on every load
#     without forbidding storage outright.
#
# --delete on the first pass removes assets from a previous build that no
# longer exist locally, which is what keeps the deploy idempotent: running it
# twice against the same build leaves the bucket in the same state.
# index.html is excluded from the first pass, deliberately, so the second
# pass is the only thing that ever writes it.
#
# Under --dry-run both aws calls carry the CLI's own --dryrun flag, so the
# CLI reports exactly what it would upload or delete without changing
# anything in the bucket.
# ---------------------------------------------------------------------------
S3_TARGET="s3://$BUCKET"

DRYRUN_ARGS=()
if [[ "$DRY_RUN" -eq 1 ]]; then
  DRYRUN_ARGS+=(--dryrun)
fi

log "syncing hashed assets with a one-year immutable cache-control"
log "+ aws s3 sync $DIST_DIR $S3_TARGET --delete --exclude index.html --cache-control ..."
aws s3 sync "$DIST_DIR" "$S3_TARGET" \
  ${AWS_ARGS[@]+"${AWS_ARGS[@]}"} \
  ${DRYRUN_ARGS[@]+"${DRYRUN_ARGS[@]}"} \
  --delete \
  --exclude "index.html" \
  --cache-control "public, max-age=31536000, immutable"

log "uploading index.html with a no-cache cache-control"
log "+ aws s3 cp $DIST_DIR/index.html $S3_TARGET/index.html --cache-control ..."
aws s3 cp "$DIST_DIR/index.html" "$S3_TARGET/index.html" \
  ${AWS_ARGS[@]+"${AWS_ARGS[@]}"} \
  ${DRYRUN_ARGS[@]+"${DRYRUN_ARGS[@]}"} \
  --cache-control "no-cache, no-store, must-revalidate"

# ---------------------------------------------------------------------------
# Invalidate index.html at the CDN edge and wait for the invalidation to
# finish, so the script does not exit while stale content is still being
# served from an edge location.
# ---------------------------------------------------------------------------
if [[ "$DRY_RUN" -eq 1 ]]; then
  log "+ aws cloudfront create-invalidation --distribution-id $DISTRIBUTION_ID --paths /index.html"
  log "dry run complete, no changes made"
  exit 0
fi

log "creating a CloudFront invalidation for /index.html"
INVALIDATION_ID="$(aws cloudfront create-invalidation \
  ${AWS_ARGS[@]+"${AWS_ARGS[@]}"} \
  --distribution-id "$DISTRIBUTION_ID" \
  --paths "/index.html" \
  --query 'Invalidation.Id' \
  --output text)"

if [[ -z "$INVALIDATION_ID" || "$INVALIDATION_ID" == "None" ]]; then
  err "CloudFront did not return an invalidation id"
  exit 4
fi

log "invalidation id: $INVALIDATION_ID, waiting for it to complete"
if ! aws cloudfront wait invalidation-completed \
  ${AWS_ARGS[@]+"${AWS_ARGS[@]}"} \
  --distribution-id "$DISTRIBUTION_ID" \
  --id "$INVALIDATION_ID"; then
  err "invalidation $INVALIDATION_ID did not complete. Check the CloudFront console."
  exit 4
fi

log "invalidation complete"
log "deploy finished: s3://$BUCKET behind distribution $DISTRIBUTION_ID"
