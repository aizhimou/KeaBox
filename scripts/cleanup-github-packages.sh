#!/usr/bin/env bash

[ -n "${BASH_VERSION:-}" ] || exec bash "$0" "$@"

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  cleanup-github-packages.sh --owner OWNER --package PACKAGE [options]

Options:
  --owner OWNER          GitHub user or org name
  --package PACKAGE      Package name, can be repeated
  --scope SCOPE          user or org (default: user)
  --type TYPE            GitHub package type (default: container)
  --keep COUNT           Keep the newest COUNT versions (default: 10)
  --delete-untagged      Delete versions without container tags first
  --dry-run              Print deletions without executing them
  -h, --help             Show this help

Examples:
  ./scripts/cleanup-github-packages.sh \
    --owner aizhimou \
    --package pigeon-pod-saas/api \
    --delete-untagged \
    --keep 5
EOF
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

urlencode_slashes() {
  echo "$1" | sed 's/\//%2F/g'
}

delete_version() {
  local endpoint="$1"
  local version_id="$2"

  if [ "$DRY_RUN" = "true" ]; then
    echo "DRY RUN delete: $endpoint/versions/$version_id"
    return
  fi

  gh api -X DELETE "$endpoint/versions/$version_id" >/dev/null
  echo "Deleted version: $version_id"
}

fetch_versions() {
  local endpoint="$1"

  gh api "$endpoint/versions" --paginate
}

cleanup_package() {
  local package_name="$1"
  local encoded_name endpoint untagged_ids stale_ids

  encoded_name="$(urlencode_slashes "$package_name")"
  endpoint="$API_PREFIX/$OWNER/packages/$PACKAGE_TYPE/$encoded_name"

  echo "--------------------------------"
  echo "Cleaning package: $package_name"

  if [ "$DELETE_UNTAGGED" = "true" ]; then
    if [ "$PACKAGE_TYPE" != "container" ]; then
      echo "Skipping untagged cleanup: only supported for container packages"
    else
      untagged_ids="$(fetch_versions "$endpoint" | jq -r -s 'add | .[] | select((.metadata.container.tags // []) | length == 0) | .id')"

      if [ -z "$untagged_ids" ]; then
        echo "No untagged versions found"
      else
        echo "$untagged_ids" | while IFS= read -r version_id; do
          [ -n "$version_id" ] || continue
          delete_version "$endpoint" "$version_id"
        done
      fi
    fi
  fi

  stale_ids="$(fetch_versions "$endpoint" | jq -r -s "add | .[${KEEP_COUNT}:] | .[].id")"

  if [ -z "$stale_ids" ]; then
    echo "No old versions to delete"
    return
  fi

  echo "$stale_ids" | while IFS= read -r version_id; do
    [ -n "$version_id" ] || continue
    delete_version "$endpoint" "$version_id"
  done
}

require_command gh
require_command jq

OWNER=""
SCOPE="user"
PACKAGE_TYPE="container"
KEEP_COUNT=10
DELETE_UNTAGGED="false"
DRY_RUN="false"
PACKAGES=()

while [ "$#" -gt 0 ]; do
  case "$1" in
    --owner)
      OWNER="${2:-}"
      shift 2
      ;;
    --package)
      PACKAGES+=("${2:-}")
      shift 2
      ;;
    --scope)
      SCOPE="${2:-}"
      shift 2
      ;;
    --type)
      PACKAGE_TYPE="${2:-}"
      shift 2
      ;;
    --keep)
      KEEP_COUNT="${2:-}"
      shift 2
      ;;
    --delete-untagged)
      DELETE_UNTAGGED="true"
      shift
      ;;
    --dry-run)
      DRY_RUN="true"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [ -z "$OWNER" ]; then
  echo "--owner is required" >&2
  usage >&2
  exit 1
fi

if [ "${#PACKAGES[@]}" -eq 0 ]; then
  echo "At least one --package is required" >&2
  usage >&2
  exit 1
fi

case "$SCOPE" in
  user)
    API_PREFIX="users"
    ;;
  org)
    API_PREFIX="orgs"
    ;;
  *)
    echo "--scope must be user or org" >&2
    exit 1
    ;;
esac

case "$KEEP_COUNT" in
  ''|*[!0-9]*)
    echo "--keep must be a non-negative integer" >&2
    exit 1
    ;;
esac

export GH_PAGER=""

for package_name in "${PACKAGES[@]}"; do
  cleanup_package "$package_name"
done
