#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/briefeed-radio-adapter.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

engine="$tmp/engine"
state="$tmp/state"
bin="$tmp/bin"
mkdir -p "$engine" "$state" "$bin"

apply_fixture() {
    local path="$1"
    local content="$2"
    printf '%s\n' "$content" > "$path"
    chmod +x "$path"
}

apply_fixture "$engine/sim-lib.sh" '#!/usr/bin/env bash
sim_state_dir() { printf "%s\n" "$RADIO_SELFTEST_STATE"; }
sim_uuid_exists() { [[ "$1" == "SELFTEST-UUID" ]]; }
sim_field() {
    case "$2" in
        name) printf "%s\n" "Briefeed-Codex-live-radio-adapter-selftest" ;;
        state) printf "%s\n" "Booted" ;;
    esac
}
sim_claims_for_uuid() { printf "%s\n" "$RADIO_SELFTEST_STATE/live-radio-adapter-selftest.env"; }
sim_is_protected() { return 1; }
sim_lease_touch() { :; }
sim_use_lock() { :; }
sim_use_unlock() { :; }
sim_acquire_boot_slot() { :; }
sim_boot_start() { :; }
sim_unlock() { :; }
sim_boot_ready() { :; }'

apply_fixture "$engine/sim-doctor.sh" '#!/usr/bin/env bash
exit 0'

apply_fixture "$engine/sim-golden.sh" '#!/usr/bin/env bash
set -euo pipefail
[[ "${1:-}" == "clone" ]]
mkdir -p "$RADIO_SELFTEST_STATE"
printf "SIM_UUID=SELFTEST-UUID\nSIM_NAME=Briefeed-Codex-live-radio-adapter-selftest\n" \
  > "$RADIO_SELFTEST_STATE/${2}.env"
printf "SIM_UUID=SELFTEST-UUID\n"'

apply_fixture "$bin/xcodebuild" '#!/usr/bin/env bash
printf "xcodebuild-called\n" > "$RADIO_SELFTEST_XCODEBUILD_MARKER"'

export RADIO_APP_TEST_ENGINE="$engine"
export RADIO_SELFTEST_STATE="$state"
export RADIO_SELFTEST_XCODEBUILD_MARKER="$tmp/xcodebuild-called"
export AGENT_SIM_PREFIX="Briefeed-Codex"
export PATH="$bin:$PATH"

test ! -e "$state/live-radio-adapter-selftest.env"
bash "$ROOT/skills/app-testing/scripts/run-radio.sh" live-radio-adapter-selftest unit
test -f "$state/live-radio-adapter-selftest.env"
test -f "$RADIO_SELFTEST_XCODEBUILD_MARKER"

mkdir -p "$state/.adapter-live-radio-adapter-selftest.lock"
rm -f "$state/.adapter-live-radio-adapter-selftest.lock/holder"
rm -f "$RADIO_SELFTEST_XCODEBUILD_MARKER"
bash "$ROOT/skills/app-testing/scripts/run-radio.sh" live-radio-adapter-selftest unit
test -f "$RADIO_SELFTEST_XCODEBUILD_MARKER"

apply_fixture "$engine/sim-doctor.sh" '#!/usr/bin/env bash
printf "%s\n" "PRESSURE=critical swap_free=100MB"
exit 0'
rm -f "$RADIO_SELFTEST_XCODEBUILD_MARKER"
set +e
bash "$ROOT/skills/app-testing/scripts/run-radio.sh" live-radio-adapter-selftest ui
critical_rc=$?
set -e
test "$critical_rc" -eq 75
test ! -e "$RADIO_SELFTEST_XCODEBUILD_MARKER"

apply_fixture "$engine/sim-doctor.sh" '#!/usr/bin/env bash
exit 10'
set +e
bash "$ROOT/skills/app-testing/scripts/run-radio.sh" live-radio-adapter-selftest ui
critical_rc=$?
set -e
test "$critical_rc" -eq 75
test ! -e "$RADIO_SELFTEST_XCODEBUILD_MARKER"

printf '%s\n' "run-radio fresh-claim, ownerless-lock, and critical-pressure self-tests passed"
