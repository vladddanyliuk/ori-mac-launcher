#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

fail=0
for f in "$ROOT/ori" "$ROOT"/lib/*.sh "$ROOT/tests/test.sh"; do
  if ! bash -n "$f"; then
    echo "syntax failed: $f" >&2
    fail=1
  fi
done

if ! grep -q 'ORI_APP_ID="1057090"' "$ROOT/lib/common.sh"; then
  echo "missing Ori Steam App ID" >&2
  fail=1
fi

exit "$fail"