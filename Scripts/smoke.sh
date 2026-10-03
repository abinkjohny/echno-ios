#!/usr/bin/env bash
#
# Runs the live smoke suite against a real backend.
#
# The suite is skipped by `swift test` unless the environment supplies a way to
# authenticate, which is what keeps the other 200 tests hermetic and offline.
# This script supplies it from `.env.smoke`, which is gitignored.
#
#   cp Scripts/smoke.env.example .env.smoke   # then fill it in
#   Scripts/smoke.sh
#
set -euo pipefail
cd "$(dirname "$0")/.."

if [ -f .env.smoke ]; then
  # shellcheck disable=SC1091
  set -a; . ./.env.smoke; set +a
fi

have_token=0
if [ -n "${ECHNO_SMOKE_ACCESS_TOKEN:-}" ] || [ -n "${ECHNO_SMOKE_REFRESH_TOKEN:-}" ]; then
  have_token=1
fi

# A username with no password, or the reverse, used to pass this check and then
# leave the suite disabled — and a disabled suite still prints
# "Test run with 2 tests in 1 suite passed". Half a password grant is a
# configuration mistake, so it is named here rather than reported as success.
if [ "$have_token" -eq 0 ]; then
  if [ -n "${ECHNO_SMOKE_USERNAME:-}" ] && [ -z "${ECHNO_SMOKE_PASSWORD:-}" ]; then
    echo "ECHNO_SMOKE_USERNAME is set but ECHNO_SMOKE_PASSWORD is not." >&2
    exit 2
  fi
  if [ -n "${ECHNO_SMOKE_PASSWORD:-}" ] && [ -z "${ECHNO_SMOKE_USERNAME:-}" ]; then
    echo "ECHNO_SMOKE_PASSWORD is set but ECHNO_SMOKE_USERNAME is not." >&2
    exit 2
  fi
fi

if [ "$have_token" -eq 0 ] && [ -z "${ECHNO_SMOKE_USERNAME:-}" ]; then
  cat >&2 <<'MSG'
No credential configured, so the smoke suite would be skipped.

Set one of these, in .env.smoke or the environment:

  ECHNO_SMOKE_REFRESH_TOKEN   an offline_access refresh token  (preferred)
  ECHNO_SMOKE_ACCESS_TOKEN    a bearer token                   (expires in minutes)
  ECHNO_SMOKE_USERNAME + ECHNO_SMOKE_PASSWORD                  (test client only)

echno-ios-client allows neither direct access grants nor the device flow, which
is the correct posture for a public PKCE client. Use a refresh token from a
signed-in session, or a separate test client for the password grant.
MSG
  exit 2
fi

# --filter matches the type name; the @Suite display name does not match here.
log=$(mktemp)
trap 'rm -f "$log"' EXIT
set +e
swift test --filter LiveSmokeTests 2>&1 | tee "$log"
status=${PIPESTATUS[0]}
set -e

# The belt to the suite's braces. swift-testing reports a skipped suite inside
# a run it still calls passed, so a green summary line is not on its own
# evidence that anything was exercised.
if grep -q "Suite \"Live backend smoke\" skipped" "$log"; then
  echo >&2
  echo "The smoke suite was SKIPPED, not run. Nothing was verified." >&2
  exit 1
fi

exit "$status"
