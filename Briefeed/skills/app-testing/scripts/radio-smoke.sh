#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
: "${SIM_UUID:?SIM_UUID is required}"
: "${DERIVED_DATA_PATH:?DERIVED_DATA_PATH is required}"
ENGINE="$HOME/ericode/skills/app-testing/scripts"
export BRIEFEED_APP_ROOT="$ROOT"
export AGENT_SIM_CONFIG="$ROOT/skills/app-testing/config.sh"
source "$ENGINE/sim-lib.sh"

evidence_root="${RADIO_EVIDENCE_DIR:-$DERIVED_DATA_PATH/RadioSmokeEvidence}"
run_id="$(date -u +%Y%m%dT%H%M%SZ)"
evidence="$evidence_root/$run_id"
screenshot="$evidence/radio-partial.png"
log_path="$evidence/radio.log"
xcresult="$DERIVED_DATA_PATH/RadioSmoke.xcresult"
receipt="$evidence/receipt.txt"
mkdir -p "$evidence"
rm -rf "$xcresult"

SIM_UUID="$SIM_UUID" DERIVED_DATA_PATH="$DERIVED_DATA_PATH" \
    with_timeout 900 bash "$ROOT/skills/app-testing/scripts/build-install.sh"

app_path="$(find "$DERIVED_DATA_PATH/Build/Products/Debug-iphonesimulator" \
    -maxdepth 1 -name 'Briefeed.app' -print -quit)"
[[ -d "$app_path" ]] || { echo "Briefeed.app not found" >&2; exit 1; }

SIM_UUID="$SIM_UUID" bash "$ROOT/skills/app-testing/scripts/radio-fixtures.sh" partial 1
with_timeout 10 sleep 3
with_timeout 30 xcrun simctl io "$SIM_UUID" screenshot "$screenshot"

(
    with_timeout 180 xcrun simctl spawn "$SIM_UUID" log stream \
        --style compact --predicate 'process == "Briefeed"' >"$log_path" 2>&1
) &
log_pid=$!
cleanup_log() {
    if kill -0 "$log_pid" 2>/dev/null; then
        kill "$log_pid" 2>/dev/null || true
        wait "$log_pid" 2>/dev/null || true
    fi
}
trap cleanup_log EXIT INT TERM

with_timeout 900 xcodebuild test \
    -project "$ROOT/Briefeed.xcodeproj" -scheme Briefeed \
    -destination "platform=iOS Simulator,id=$SIM_UUID" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    -parallel-testing-enabled NO \
    -maximum-concurrent-test-simulator-destinations 1 \
    -resultBundlePath "$xcresult" \
    -only-testing:BriefeedUITests/RadioUITests/testHeadlessRadioSmoke

cleanup_log
trap - EXIT INT TERM

cat >"$receipt" <<EOF
simulator_uuid=$SIM_UUID
git_sha=$(git -C "$ROOT/.." rev-parse HEAD)
app_path=$app_path
screenshot_path=$screenshot
log_path=$log_path
xcresult_path=$xcresult
EOF

printf 'RADIO_SMOKE_RECEIPT=%s\n' "$receipt"
