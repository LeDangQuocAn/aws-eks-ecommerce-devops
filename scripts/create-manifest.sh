#!/bin/bash

set -euo pipefail

repository="${1:-}"
tag="${2:-}"

if [ -z "$repository" ]; then
  echo "Error: First argument must be repository"
  exit 1
fi

if [ -z "$tag" ]; then
  echo "Error: Second argument must be tag"
  exit 1
fi

target_manifest="${repository}:${tag}"
arch_refs=()

resolve_ref() {
  local source_ref="$1"
  local arch="$2"

  local inspect_json
  inspect_json="$(docker manifest inspect "$source_ref")"

  # If source_ref is a manifest list/index, extract the concrete image digest for the requested arch.
  local digest
  digest="$(echo "$inspect_json" | jq -r --arg arch "$arch" '.manifests[]? | select(.platform.architecture == $arch) | .digest' | head -n1)"

  if [ -n "$digest" ] && [ "$digest" != "null" ]; then
    echo "${repository}@${digest}"
  else
    echo "$source_ref"
  fi
}

if docker manifest inspect "${repository}:${tag}-amd64" >/dev/null 2>&1; then
  arch_refs+=("$(resolve_ref "${repository}:${tag}-amd64" "amd64")")
else
  echo "Info: Missing amd64 image tag ${repository}:${tag}-amd64"
fi

if docker manifest inspect "${repository}:${tag}-arm64" >/dev/null 2>&1; then
  arch_refs+=("$(resolve_ref "${repository}:${tag}-arm64" "arm64")")
else
  echo "Info: Missing arm64 image tag ${repository}:${tag}-arm64"
fi

if [ ${#arch_refs[@]} -eq 0 ]; then
  echo "Error: No architecture images found for ${repository}:${tag}-amd64 or ${repository}:${tag}-arm64"
  exit 1
fi

echo "Creating manifest ${target_manifest} from: ${arch_refs[*]}"
docker manifest rm "${target_manifest}" >/dev/null 2>&1 || true
docker manifest create "${target_manifest}" "${arch_refs[@]}"
docker manifest push "${target_manifest}"