#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
SCRIPT="$ROOT/BriefeedTests/Fixtures/Transcription/apple-news-script.txt"
OUTPUT="$ROOT/BriefeedTests/Fixtures/Transcription/apple-news-fixture.aiff"

mkdir -p "$(dirname "$OUTPUT")"
if ! /usr/bin/say -v Samantha -r 150 -f "$SCRIPT" -o "$OUTPUT" --file-format=AIFF --data-format=LEI16@22050; then
    # Older macOS `say` builds omit output-format flags; retain equivalent AIFF output there.
    SOURCE="$OUTPUT.source.aiff"
    /usr/bin/say -v Samantha -r 150 -f "$SCRIPT" -o "$SOURCE"
    /usr/bin/afconvert -f AIFF -d BEI16@22050 "$SOURCE" "$OUTPUT"
    /bin/rm -f "$SOURCE"
fi
/usr/bin/afinfo "$OUTPUT" | /usr/bin/grep -q 'estimated duration'
