#!/usr/bin/env bash
set -euo pipefail
actual=$(git rev-parse HEAD)
if [[ -n "${QUALIFICATION_SHA:-}" ]]; then
  [[ "$QUALIFICATION_SHA" =~ ^[0-9a-f]{40}$ && "$actual" == "$QUALIFICATION_SHA" ]] || {
    echo 'SHA de qualification absent, invalide ou différent du checkout.' >&2
    exit 1
  }
fi
mkdir -p artifacts/qualification
printf '{"commit":"%s","run":"%s","attempt":"%s"}\n' "$actual" "${GITHUB_RUN_ID:-local}" "${GITHUB_RUN_ATTEMPT:-1}" > artifacts/qualification/identity.json
