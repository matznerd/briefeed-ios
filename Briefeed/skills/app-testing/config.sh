#!/usr/bin/env bash
BRIEFEED_APP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export BRIEFEED_APP_ROOT
export AGENT_SIM_PREFIX="Briefeed-Codex"
export AGENT_SIM_BUNDLE_ID="Matznerd.Briefeed"
export AGENT_SIM_STABLE_MAX_MAJOR=18
export AGENT_SIM_GOLDEN_INSTALL_HOOK='SIM_UUID=$GOLDEN_UUID bash "$BRIEFEED_APP_ROOT/skills/app-testing/scripts/build-install.sh"'
