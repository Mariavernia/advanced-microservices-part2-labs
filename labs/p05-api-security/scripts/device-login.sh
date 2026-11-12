#!/usr/bin/env bash
set -euo pipefail
# Obtain a real user access token through OAuth 2.0 Device Authorization Grant.
# No username/password or client secret is handled by this script.
profile="${1:-}"
[[ "$profile" == "reader" || "$profile" == "admin" ]] || {
  echo "Usage: bash labs/p05-api-security/scripts/device-login.sh reader|admin" >&2; exit 2;
}
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
# shellcheck disable=SC1090
source "$root/config/course.env"
issuer="${OIDC_ISSUER_URI:-}"
client="${OIDC_CLIENT_ID:-advanced-orders-cli}"
[[ "$issuer" == https://* ]] || { echo "Instructor must configure the Keycloak HTTPS issuer first." >&2; exit 2; }
for bin in curl jq; do command -v "$bin" >/dev/null || { echo "Missing $bin" >&2; exit 1; }; done
metadata="$(curl -fsS --max-time 15 "${issuer%/}/.well-known/openid-configuration")"
device_endpoint="$(jq -r '.device_authorization_endpoint // empty' <<<"$metadata")"
token_endpoint="$(jq -r '.token_endpoint // empty' <<<"$metadata")"
[[ -n "$device_endpoint" && -n "$token_endpoint" ]] || { echo "Device flow not available at this issuer." >&2; exit 1; }
response="$(curl -fsS --max-time 15 -X POST "$device_endpoint" \
  --data-urlencode "client_id=$client" --data-urlencode "scope=openid profile")"
device_code="$(jq -r '.device_code // empty' <<<"$response")"
user_code="$(jq -r '.user_code // empty' <<<"$response")"
verify_uri="$(jq -r '.verification_uri_complete // .verification_uri // empty' <<<"$response")"
interval="$(jq -r '.interval // 5' <<<"$response")"
lifetime="$(jq -r '.expires_in // 600' <<<"$response")"
[[ -n "$device_code" && -n "$user_code" && "$interval" =~ ^[0-9]+$ && "$lifetime" =~ ^[0-9]+$ ]] || {
  echo "Unexpected device authorization response (check Keycloak client setup)." >&2; exit 1;
}
(( interval < 2 )) && interval=2
printf 'Open in your browser: %s\nUser code: %s\n' "$verify_uri" "$user_code"
printf 'Authenticate as the instructor-assigned %s user. The access token will NOT be displayed.\n' "$profile"
deadline=$((SECONDS + lifetime))
access_token=""
while ((SECONDS < deadline)); do
  sleep "$interval"
  token_response="$(curl -sS --max-time 15 -X POST "$token_endpoint" \
    --data-urlencode "client_id=$client" \
    --data-urlencode 'grant_type=urn:ietf:params:oauth:grant-type:device_code' \
    --data-urlencode "device_code=$device_code" || true)"
  access_token="$(jq -r '.access_token // empty' <<<"$token_response")"
  [[ -n "$access_token" ]] && break
  error="$(jq -r '.error // empty' <<<"$token_response")"
  case "$error" in
    authorization_pending) ;;
    slow_down) interval=$((interval + 5));;
    access_denied|expired_token|invalid_grant|invalid_client)
      echo "Keycloak device authorization ended with: $error" >&2; exit 1;;
    *) echo "Unexpected device token result: ${error:-empty response}" >&2; exit 1;;
  esac
done
[[ -n "$access_token" ]] || { echo "Authentication expired. Restart the device authorization flow." >&2; exit 1; }
umask 077
dir="$HOME/.cache/advanced-orders"
mkdir -p "$dir"
printf '%s' "$access_token" > "$dir/$profile.jwt"
chmod 600 "$dir/$profile.jwt"
unset access_token device_code token_response response
echo "[PASS] Access token stored in an owner-only file under ~/.cache/advanced-orders (not Git)."
echo "Do not paste or commit token files. Run verify.sh after both reader and admin sign in."
