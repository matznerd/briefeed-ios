#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
ENGINE="${RADIO_APP_TEST_ENGINE:-$HOME/ericode/skills/app-testing/scripts}"
export AGENT_SIM_CONFIG="$ROOT/skills/app-testing/config.sh"
source "$ENGINE/sim-lib.sh"

lane="$(printf '%s' "${1:?lane key required}" | tr -cs '[:alnum:]_.-' '-' | sed 's/^-*//;s/-*$//')"
mode="${2:?mode unit, ui, or smoke required}"
[[ -n "$lane" ]] || exit 75
[[ "$mode" == unit || "$mode" == ui || "$mode" == smoke ]] || exit 64

state_dir="$(sim_state_dir)"
mkdir -p "$state_dir"
lane_lock="$state_dir/.adapter-$lane.lock"
if ! mkdir "$lane_lock" 2>/dev/null; then
    holder="$(sed -n 's/^pid=//p' "$lane_lock/holder" 2>/dev/null | head -1)"
    if [[ -n "$holder" ]] && kill -0 "$holder" 2>/dev/null; then
        echo "Radio lane $lane is owned by pid $holder" >&2
        exit 75
    fi
    age=$(( $(date +%s) - $(stat -f %m "$lane_lock" 2>/dev/null || echo 0) ))
    (( age >= 10 )) || exit 75
    rm -rf "$lane_lock"
    mkdir "$lane_lock" || exit 75
fi
printf 'pid=%s\n' "$$" > "$lane_lock/holder"

sim_uuid=""
state_file="$state_dir/$lane.env"
use_locked=0
cleanup() {
    rc=$?
    trap - EXIT INT TERM
    if [[ "$use_locked" == 1 ]]; then
        sim_lease_touch "$state_file"
        sim_use_unlock "$sim_uuid"
    fi
    rm -rf "$lane_lock"
    exit "$rc"
}
trap cleanup EXIT INT TERM

doctor_rc=0
bash "$ENGINE/sim-doctor.sh" --gc || doctor_rc=$?
[[ "$doctor_rc" == 0 || "$doctor_rc" == 10 ]] || exit 75
if [[ "$doctor_rc" == 10 ]]; then
    echo "Radio lane $lane will not start new work while host pressure is critical" >&2
    exit 75
fi

sim_uuid="$(sed -n 's/^SIM_UUID=//p' "$state_file" 2>/dev/null | tail -1 || true)"
recorded_name="$(sed -n 's/^SIM_NAME=//p' "$state_file" 2>/dev/null | tail -1 || true)"
sim_name=""
valid_claim=0
claim_exists=0
[[ -e "$state_file" ]] && claim_exists=1
if [[ "$claim_exists" == 1 && -n "$sim_uuid" ]] && sim_uuid_exists "$sim_uuid"; then
    sim_name="$(sim_field "$sim_uuid" name)"
    claims="$(sim_claims_for_uuid "$sim_uuid")"
    if [[ -n "$recorded_name" && "$recorded_name" == "$sim_name" \
          && "$sim_name" == "$AGENT_SIM_PREFIX-"* \
          && "$claims" == "$state_file" ]] \
          && ! sim_is_protected "$sim_uuid"; then
        valid_claim=1
    fi
fi

if [[ "$claim_exists" == 1 && "$valid_claim" != 1 ]]; then
    echo "Radio lane claim is malformed or not uniquely owned: $state_file" >&2
    exit 75
fi

if [[ "$valid_claim" != 1 ]]; then
    [[ "$doctor_rc" != 10 ]] || exit 75
    clone_output="$(bash "$ENGINE/sim-golden.sh" clone "$lane")" || exit 75
    sim_uuid="$(printf '%s\n' "$clone_output" | sed -n 's/^SIM_UUID=//p' | tail -1)"
    [[ -n "$sim_uuid" ]] || exit 75
    state_file="$state_dir/$lane.env"
    sim_name="$(sim_field "$sim_uuid" name)"
    recorded_name="$(sed -n 's/^SIM_NAME=//p' "$state_file" 2>/dev/null | tail -1)"
    claims="$(sim_claims_for_uuid "$sim_uuid")"
    [[ -n "$recorded_name" && "$recorded_name" == "$sim_name" ]] || exit 75
    [[ "$sim_name" == "$AGENT_SIM_PREFIX-"* ]] || exit 75
    [[ "$claims" == "$state_file" ]] || exit 75
    sim_is_protected "$sim_uuid" && exit 75
    sim_use_lock "$sim_uuid" "$$" "briefeed-$mode-$lane" || exit 75
    use_locked=1
else
    sim_lease_touch "$state_file"
    sim_use_lock "$sim_uuid" "$$" "briefeed-$mode-$lane" || exit 75
    use_locked=1
    if [[ "$(sim_field "$sim_uuid" state)" != Booted ]]; then
        sim_acquire_boot_slot || exit 75
        boot_rc=0
        sim_boot_start "$sim_uuid" || boot_rc=$?
        sim_unlock
        [[ "$boot_rc" == 0 ]] || exit 75
        sim_boot_ready "$sim_uuid" || exit 75
    fi
fi

derived="/tmp/briefeed-radio-$lane-derived-data"
case "$mode" in
unit)
    selector="${RADIO_TEST_SELECTOR:-BriefeedTests}"
    xcodebuild test -project "$ROOT/Briefeed.xcodeproj" -scheme Briefeed \
      -destination "platform=iOS Simulator,id=$sim_uuid" \
      -derivedDataPath "$derived" -parallel-testing-enabled NO \
      -maximum-concurrent-test-simulator-destinations 1 \
      -only-testing:"$selector"
    ;;
ui)
    selector="${RADIO_UI_TEST_SELECTOR:-BriefeedUITests/RadioUITests}"
    xcodebuild test -project "$ROOT/Briefeed.xcodeproj" -scheme Briefeed \
      -destination "platform=iOS Simulator,id=$sim_uuid" \
      -derivedDataPath "$derived" -parallel-testing-enabled NO \
      -maximum-concurrent-test-simulator-destinations 1 \
      -only-testing:"$selector"
    ;;
smoke)
    SIM_UUID="$sim_uuid" DERIVED_DATA_PATH="$derived" \
      bash "$ROOT/skills/app-testing/scripts/radio-smoke.sh"
    ;;
esac
