#!/usr/bin/env bash
set -euo pipefail

APP_BUNDLE_ID="${APP_BUNDLE_ID:-Matznerd.Briefeed}"
IPA_PATH="${IPA_PATH:-/tmp/briefeed-export-auth-clean/Briefeed.ipa}"
VERIFY_TIMEOUT="${VERIFY_TIMEOUT:-10m}"
LOCALE="${LOCALE:-en-US}"
TEST_NOTES="${TEST_NOTES:-PocketTTS local briefing playback: Reddit story Play Now fetches content, summarizes with Gemini, generates local PocketTTS audio, caches it, and plays through the unified player.}"

if ! command -v asc >/dev/null 2>&1; then
  echo "error: asc CLI is not installed or not on PATH" >&2
  exit 127
fi

if [ ! -f "$IPA_PATH" ]; then
  echo "error: IPA not found at $IPA_PATH" >&2
  echo "Build/export the app first, or set IPA_PATH=/path/to/Briefeed.ipa" >&2
  exit 1
fi

app_json="$(asc apps list --bundle-id "$APP_BUNDLE_ID" --output json)"
app_count="$(printf '%s' "$app_json" | /usr/bin/python3 -c 'import json,sys; print(len(json.load(sys.stdin).get("data", [])))')"

if [ "$app_count" = "0" ]; then
  echo "error: no App Store Connect app record found for bundle id $APP_BUNDLE_ID" >&2
  echo "Create the app record first. See Briefeed/docs/handoff/pockettts-testflight-handoff.md" >&2
  exit 2
fi

if [ "$app_count" != "1" ]; then
  echo "error: expected one app record for $APP_BUNDLE_ID, found $app_count" >&2
  exit 3
fi

app_id="$(printf '%s' "$app_json" | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin)["data"][0]["id"])')"

echo "Uploading $IPA_PATH to App Store Connect app $app_id ($APP_BUNDLE_ID)"

asc builds upload \
  --app "$app_id" \
  --ipa "$IPA_PATH" \
  --test-notes "$TEST_NOTES" \
  --locale "$LOCALE" \
  --verify-timeout "$VERIFY_TIMEOUT"
