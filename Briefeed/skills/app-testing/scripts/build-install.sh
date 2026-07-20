#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
: "${SIM_UUID:?SIM_UUID is required}"
ENGINE="$HOME/ericode/skills/app-testing/scripts"
export AGENT_SIM_CONFIG="$ROOT/skills/app-testing/config.sh"
source "$ENGINE/sim-lib.sh"

derived="${DERIVED_DATA_PATH:-/tmp/briefeed-radio-golden-derived-data}"
xcodebuild build -project "$ROOT/Briefeed.xcodeproj" -scheme Briefeed \
  -configuration Debug -destination "platform=iOS Simulator,id=$SIM_UUID" \
  -derivedDataPath "$derived" COMPILER_INDEX_STORE_ENABLE=NO
app_path="$(find "$derived/Build/Products/Debug-iphonesimulator" -maxdepth 1 -name 'Briefeed.app' -print -quit)"
[[ -d "$app_path" ]] || { echo "Briefeed.app not found" >&2; exit 1; }
sim_install_if_changed "$SIM_UUID" "$app_path" "$AGENT_SIM_BUNDLE_ID"
