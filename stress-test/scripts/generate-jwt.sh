#!/usr/bin/env bash
# Mints an HS256 JWT for load testing. Works with any service that validates
# HS256 bearer tokens (including this repo's ingestion service).
#
# Usage:
#   ./scripts/generate-jwt.sh <jwt-secret> [ttl-seconds]
#
# Example:
#   export JWT_TOKEN=$(./scripts/generate-jwt.sh "$JWT_SECRET" 3600)
set -euo pipefail

SECRET="${1:?usage: generate-jwt.sh <jwt-secret> [ttl-seconds]}"
TTL="${2:-86400}"
USER_ID="${3:-loadtest}"

b64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }

now=$(date +%s)
header='{"alg":"HS256","typ":"JWT"}'
payload=$(printf '{"userId":"%s","role":"ingest","iat":%s,"exp":%s}' "$USER_ID" "$now" "$((now + TTL))")

H=$(printf '%s' "$header" | b64url)
P=$(printf '%s' "$payload" | b64url)
SIG=$(printf '%s' "$H.$P" | openssl dgst -sha256 -hmac "$SECRET" -binary | b64url)

printf '%s.%s.%s' "$H" "$P" "$SIG"
