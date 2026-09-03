#!/usr/bin/env bash
# Resolve and validate the mobile release version, emit `version` + `tag`.
#
# Sources (first match wins):
#   1. $APP_VERSION env (workflow_dispatch input)
#   2. git tag on HEAD matching v* (push tag trigger)
#   3. fallback 0.1.0
#
# Emits to $GITHUB_OUTPUT when running in Actions; always prints to stdout.
set -euo pipefail

raw="${APP_VERSION:-}"

if [[ -z "$raw" ]]; then
  # Try the tag that triggered the run.
  ref="${GITHUB_REF_NAME:-}"
  if [[ "$ref" =~ ^v[0-9] ]]; then
    raw="${ref#v}"
  fi
fi

version="${raw:-0.1.0}"

# Strip a leading v and any build suffix for validation.
core="${version#v}"
core="${core%%+*}"

if ! [[ "$core" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "ERROR: '$version' is not valid semver (x.y.z)" >&2
  exit 1
fi

tag="v${core}"

echo "version=$core"
echo "tag=$tag"

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "version=$core"
    echo "tag=$tag"
  } >> "$GITHUB_OUTPUT"
fi
