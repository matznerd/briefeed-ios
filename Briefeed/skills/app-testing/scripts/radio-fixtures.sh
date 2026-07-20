#!/usr/bin/env bash
set -euo pipefail

: "${BRIEFEED_APP_ROOT:?BRIEFEED_APP_ROOT is required}"
: "${SIM_UUID:?SIM_UUID is required}"
ENGINE="$HOME/ericode/skills/app-testing/scripts"
export AGENT_SIM_CONFIG="$BRIEFEED_APP_ROOT/skills/app-testing/config.sh"
source "$ENGINE/sim-lib.sh"

scenario="${1:?fixture scenario is required}"
reset="${2:-0}"
case "$scenario" in
partial|completed|offline|all-failed|degraded|no-sources|refreshing|exhausted) ;;
*) echo "Unknown Radio fixture scenario: $scenario" >&2; exit 64 ;;
esac
[[ "$reset" == 0 || "$reset" == 1 ]] || { echo "reset must be 0 or 1" >&2; exit 64; }

SIMCTL_CHILD_BRIEFEED_RADIO_RESET_STORE="$reset" \
    with_timeout 30 xcrun simctl launch --terminate-running-process \
    "$SIM_UUID" "$AGENT_SIM_BUNDLE_ID" \
    -briefeed-radio-fixture "$scenario"
