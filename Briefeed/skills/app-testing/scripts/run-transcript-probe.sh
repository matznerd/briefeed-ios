#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
bash "$ROOT/skills/app-testing/scripts/make-transcript-fixture.sh"

BRIEFEED_TRANSCRIPT_ALLOW_ASSET_DOWNLOAD=1 \
RADIO_TEST_SELECTOR=BriefeedTests/AppleSpeechAnalyzerIntegrationTests \
  bash "$ROOT/skills/app-testing/scripts/run-radio.sh" transcript-probe unit
