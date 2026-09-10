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

if [ -z "${ECHNO_SMOKE_ACCESS_TOKEN:-}" ] \
  && [ -z "${ECHNO_SMOKE_REFRESH_TOKEN:-}" ] \
  && [ -z "${ECHNO_SMOKE_USERNAME:-}" ]; then
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
exec swift test --filter LiveSmokeTests
