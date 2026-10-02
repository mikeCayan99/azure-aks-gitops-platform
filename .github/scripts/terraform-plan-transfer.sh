#!/usr/bin/env bash
set -euo pipefail
: "${PLAN_KEY:?Plan encryption key is required}"
[[ ${#PLAN_KEY} -ge 32 ]] || { echo 'Plan encryption key must have at least 32 characters' >&2; exit 1; }
: "${RUNNER_TEMP:?}"
: "${GITHUB_SHA:?}"
export GNUPGHOME="$RUNNER_TEMP/terraform-gnupg"
mkdir -p "$GNUPGHOME"
chmod 700 "$GNUPGHOME"
case "${1:-}" in
  seal)
    (
      cd infrastructure/azure
      sha256sum integration.tfplan > plan.sha256
      printf '%s\n' "$GITHUB_SHA" > revision.txt
      tar -cf "$RUNNER_TEMP/plan.tar" integration.tfplan plan.sha256 revision.txt
    )
    printf '%s' "$PLAN_KEY" | gpg --batch --yes --pinentry-mode loopback --passphrase-fd 0 \
      --symmetric --cipher-algo AES256 --output "$RUNNER_TEMP/plan.gpg" "$RUNNER_TEMP/plan.tar"
    ;;
  open)
    printf '%s' "$PLAN_KEY" | gpg --batch --yes --pinentry-mode loopback --passphrase-fd 0 \
      --output "$RUNNER_TEMP/plan.tar" --decrypt "$RUNNER_TEMP/plan.gpg"
    tar -xf "$RUNNER_TEMP/plan.tar" -C infrastructure/azure integration.tfplan plan.sha256 revision.txt
    (
      cd infrastructure/azure
      sha256sum -c plan.sha256
      [[ "$(cat revision.txt)" == "$GITHUB_SHA" ]] || { echo 'Plan source revision mismatch' >&2; exit 1; }
    )
    ;;
  *) echo 'Expected seal or open' >&2; exit 1 ;;
esac
