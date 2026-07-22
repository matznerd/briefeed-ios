#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
SCRIPT="$ROOT/BriefeedTests/Fixtures/Transcription/apple-news-script.txt"
OUTPUT="$ROOT/BriefeedTests/Fixtures/Transcription/apple-news-fixture.aiff"
OUTPUT_DIRECTORY="$(dirname "$OUTPUT")"
mkdir -p "$OUTPUT_DIRECTORY"
TEMPORARY_DIRECTORY="$(mktemp -d "$OUTPUT_DIRECTORY/.apple-news-fixture.XXXXXX")"
CANDIDATE="$TEMPORARY_DIRECTORY/apple-news-fixture.aiff"
SOURCE="$TEMPORARY_DIRECTORY/apple-news-fixture.source.aiff"

cleanup() {
    /bin/rm -rf "$TEMPORARY_DIRECTORY"
}
trap cleanup EXIT INT TERM

validate_candidate() {
    local candidate="$1"
    local info

    [[ -s "$candidate" ]] || return 1
    info="$(/usr/bin/afinfo "$candidate" 2>/dev/null)" || return 1
    [[ "$info" == *"File type ID:   AIFF"* ]] || return 1
    [[ "$info" == *"22050 Hz"* ]] || return 1
    [[ "$info" == *"16-bit big-endian signed integer"* ]] || return 1
    [[ "$info" == *"estimated duration:"* ]] || return 1
}

primary_status=0
/usr/bin/say -v Samantha -r 150 -f "$SCRIPT" -o "$CANDIDATE" --file-format=AIFF --data-format=BEI16@22050 || primary_status=$?

fallback_used=0
if (( primary_status != 0 )) || ! validate_candidate "$CANDIDATE"; then
    fallback_used=1
    /bin/rm -f "$CANDIDATE"
    # Older macOS `say` builds omit output-format flags; convert their AIFF output.
    /usr/bin/say -v Samantha -r 150 -f "$SCRIPT" -o "$SOURCE"
    /usr/bin/afconvert -f AIFF -d BEI16@22050 "$SOURCE" "$CANDIDATE"
    validate_candidate "$CANDIDATE"
fi

candidate_info="$(/usr/bin/afinfo "$CANDIDATE")"
candidate_duration="$(printf '%s\n' "$candidate_info" | /usr/bin/sed -n 's/^estimated duration: \([^ ]*\) sec$/\1/p')"
[[ -n "$candidate_duration" ]]
candidate_sha="$(/usr/bin/shasum -a 256 "$CANDIDATE" | /usr/bin/awk '{print $1}')"

printf 'TRANSCRIPT_FIXTURE_CANDIDATE_VALIDATED=%s\n' "$CANDIDATE"
printf 'TRANSCRIPT_FIXTURE_PRIMARY_STATUS=%s\n' "$primary_status"
printf 'TRANSCRIPT_FIXTURE_FALLBACK_USED=%s\n' "$fallback_used"
printf 'TRANSCRIPT_FIXTURE_CANDIDATE_DURATION_SECONDS=%s\n' "$candidate_duration"
printf 'TRANSCRIPT_FIXTURE_CANDIDATE_SHA256=%s\n' "$candidate_sha"
/bin/mv -f "$CANDIDATE" "$OUTPUT"
printf 'TRANSCRIPT_FIXTURE_REPLACED=%s\n' "$OUTPUT"
