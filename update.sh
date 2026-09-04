#!/usr/bin/env bash
#
# Pin flake.nix to a Hermes Agent GitHub Release tag and refresh flake.lock.
#
# Default: latest non-prerelease from
#   https://api.github.com/repos/NousResearch/hermes-agent/releases/latest
# Optional: ./update.sh v2026.8.31
#
# Does not bump nixpkgs. Does not commit.

set -euo pipefail

cd "$(dirname "$(readlink -f "$0")")"

if [[ "${HERMES_DESKTOP_UPDATE_ENV:-}" != 1 ]]; then
  exec nix shell --inputs-from . \
    nixpkgs#bash \
    nixpkgs#curl \
    nixpkgs#jq \
    nixpkgs#coreutils \
    nixpkgs#gnused \
    nixpkgs#nix \
    --command env HERMES_DESKTOP_UPDATE_ENV=1 bash ./update.sh "$@"
fi

REPO="NousResearch/hermes-agent"
FLAKE_URL_RE='url = "github:NousResearch/hermes-agent/'

read_flake_tag() {
  sed -n "s|^[[:space:]]*${FLAKE_URL_RE}\\(.*\\)\";$|\\1|p" flake.nix | head -n1
}

curl_gh() {
  local url="$1"
  local args=(--retry 3 --retry-all-errors -fsSL
    -H "Accept: application/vnd.github+json"
    -H "X-GitHub-Api-Version: 2022-11-28")
  if [ -n "${GITHUB_TOKEN:-}" ]; then
    args+=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
  fi
  curl "${args[@]}" "$url"
}

case $# in
  0)
    latest="$(curl_gh "https://api.github.com/repos/${REPO}/releases/latest")"
    tag="$(jq -er '.tag_name' <<<"$latest")"
    ;;
  1)
    tag="$1"
    ;;
  *)
    echo "usage: $0 [vYYYY.M.D GitHub Release tag]" >&2
    exit 2
    ;;
esac

if [[ ! "$tag" =~ ^v[0-9][0-9A-Za-z._-]*$ ]]; then
  echo "error: invalid release tag: $tag" >&2
  exit 1
fi

current_tag="$(read_flake_tag)"
if [ -z "$current_tag" ]; then
  echo "error: could not read hermes-agent release tag from flake.nix" >&2
  exit 1
fi

lock_ref="$(jq -r '.nodes["hermes-agent"].original.ref // empty' flake.lock)"

if [ "$tag" = "$current_tag" ] && [ "$lock_ref" = "$tag" ]; then
  echo "already at $tag"
  exit 0
fi

echo "$current_tag -> $tag" >&2

sed -i -E "s|(${FLAKE_URL_RE})[^\"]+\";|\\1${tag}\";|" flake.nix

if [ "$(read_flake_tag)" != "$tag" ]; then
  echo "error: failed to write release tag to flake.nix" >&2
  exit 1
fi

nix flake lock --update-input hermes-agent

if [ "$(jq -er '.nodes["hermes-agent"].original.ref' flake.lock)" != "$tag" ]; then
  echo "error: flake.lock did not pin hermes-agent to $tag" >&2
  exit 1
fi

rev="$(jq -er '.nodes["hermes-agent"].locked.rev' flake.lock)"
echo "flake.nix + flake.lock updated to $tag ($rev)"
